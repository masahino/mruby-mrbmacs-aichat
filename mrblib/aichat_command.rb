module Mrbmacs
  module Command
    def aichat
      set_aichat_target_buffer(@current_buffer) unless aichat_buffer?(@current_buffer)
      ensure_aichat_model
      buffer_name = AichatExtension::AICHAT_BUFFER_NAME
      existing_buffer = Mrbmacs.get_buffer_from_name(@buffer_list, buffer_name)
      setup_result_buffer(buffer_name)
      update_aichat_modeline
      unless existing_buffer.nil?
        apply_pending_aichat_response
        return
      end

      reset_aichat_buffer
    end

    def aichat_model
      state = @ext.data['aichat']
      if state['request_running']
        message 'AI Chat request is already running'
        return
      end

      ensure_aichat_model
      api_key = ENV['OPENAI_API_KEY']
      if api_key.nil? || api_key.empty?
        select_aichat_model(state['models'])
        return
      end

      state['request_running'] = true
      state['runner'].call(aichat_models_curl_arguments, '') do |response_body,
                                                               error_text,
                                                               status|
        models, error = parse_aichat_models(response_body, error_text, status, api_key)
        state['request_running'] = false
        if error.nil?
          state['models'] = models
        else
          message "Could not refresh AI models: #{error}"
        end
        select_aichat_model(state['models'])
      rescue StandardError => e
        state['request_running'] = false
        message "Could not refresh AI models: #{redact_aichat_secret(e.to_s, api_key)}"
        select_aichat_model(state['models'])
      end
    rescue StandardError => e
      state['request_running'] = false unless state.nil?
      message "Could not refresh AI models: #{redact_aichat_secret(e.to_s, api_key)}"
    end

    def aichat_send
      unless @current_buffer.name == AichatExtension::AICHAT_BUFFER_NAME
        message 'aichat-send is only available in *AI Chat*'
        return
      end

      if @ext.data['aichat']['request_running']
        message 'AI Chat request is already running'
        return
      end

      view = @frame.view_win
      input_start = @ext.data['aichat']['input_start']
      current_pos = view.sci_get_current_pos
      return if input_start.nil? || current_pos < input_start

      prompt = view.sci_get_text_range(input_start, current_pos)
      return if prompt.strip.empty?

      start_aichat_request(prompt, prompt)
    end

    def aichat_ask
      if @ext.data['aichat']['request_running']
        message 'AI Chat request is already running'
        return
      end

      set_aichat_target_buffer(@current_buffer)
      source_view = @frame.view_win
      selection_start = source_view.sci_get_selection_start
      selection_end = source_view.sci_get_selection_end
      region_selected = selection_start != selection_end
      source = if region_selected
                 source_view.sci_get_text_range(selection_start, selection_end)
               else
                 source_view.sci_get_text(source_view.sci_get_length + 1)
               end
      if source.bytesize > AichatExtension::MAX_EDITOR_CONTEXT_BYTES
        message "AI context is too large (#{source.bytesize} bytes; limit " \
                "#{AichatExtension::MAX_EDITOR_CONTEXT_BYTES}). " \
                'Select a smaller region and retry.'
        return
      end
      source = source.dup

      prompt = region_selected ? 'AI about region: ' : 'AI about whole buffer: '
      instruction = @frame.echo_gets(prompt)
      return if instruction.nil? || instruction.strip.empty?

      api_prompt = "User instruction:\n#{instruction}\n\n" \
                   "Editor context for this request:\n#{source}"
      aichat
      waiting_start, waiting_end, preserve_input = append_aichat_ask(instruction)
      start_aichat_request(
        api_prompt,
        instruction,
        waiting_start,
        waiting_end,
        preserve_input
      )
    end

    def aichat_clear
      state = @ext.data['aichat']
      if state['request_running']
        message 'AI Chat request is already running'
        return
      end

      state['conversation'] = []
      state['pending_response'] = nil
      ensure_aichat_model
      setup_result_buffer(AichatExtension::AICHAT_BUFFER_NAME)
      update_aichat_modeline
      reset_aichat_buffer
    end

    private

    def aichat_buffer?(buffer)
      !buffer.nil? && buffer.name == AichatExtension::AICHAT_BUFFER_NAME
    end

    def set_aichat_target_buffer(buffer)
      @ext.data['aichat']['target_buffer'] = buffer
    end

    def aichat_target_buffer
      state = @ext.data['aichat']
      target = state['target_buffer']
      return nil if target.nil?
      return target if @buffer_list.include?(target)

      state['target_buffer'] = nil
      nil
    end

    def aichat_target_name
      target = aichat_target_buffer
      return 'none' if target.nil?
      return target.name if target.filename.nil? || target.filename.empty?

      filename = File.expand_path(target.filename)
      unless @project.nil?
        root = File.expand_path(@project.root_directory)
        prefix = root.end_with?('/') ? root : "#{root}/"
        return filename[prefix.bytesize..-1] if filename.start_with?(prefix)
      end
      filename
    end

    def select_aichat_model(models)
      state = @ext.data['aichat']
      current_model = state['model']
      selected_model = @frame.echo_gets('AI model: ', current_model) do |input_text|
        matching_models = models.select do |model|
          model.start_with?(input_text)
        end
        separator = @frame.echo_win.sci_autoc_get_separator.chr
        [matching_models.join(separator), input_text.length]
      end
      return if selected_model.nil? || selected_model.empty? || selected_model == current_model

      unless models.include?(selected_model)
        message "Unknown AI model: #{selected_model}"
        return
      end

      state['model'] = selected_model
      update_aichat_modeline
    end

    def ensure_aichat_model
      state = @ext.data['aichat']
      return state['model'] unless state['model'].nil? || state['model'].empty?

      model = ENV['MRBMACS_AICHAT_MODEL']
      model = AichatExtension::DEFAULT_MODEL if model.nil? || model.empty?
      state['model'] = model
    end

    def update_aichat_modeline
      buffer = Mrbmacs.get_buffer_from_name(
        @buffer_list,
        AichatExtension::AICHAT_BUFFER_NAME
      )
      return if buffer.nil?

      state = @ext.data['aichat']
      buffer.additional_info = "#{state['model']} | Target: #{aichat_target_name}"
      @frame.modeline(self) if @current_buffer.equal?(buffer)
    end

    def aichat_models_curl_arguments
      [
        '--disable',
        '--silent',
        '--show-error',
        '--fail-with-body',
        '--connect-timeout', AichatExtension::CONNECT_TIMEOUT_SECONDS.to_s,
        '--max-time', AichatExtension::REQUEST_TIMEOUT_SECONDS.to_s,
        '--request', 'GET',
        '--url', AichatExtension::MODELS_URL,
        '--variable', '%OPENAI_API_KEY',
        '--expand-header', 'Authorization: Bearer {{OPENAI_API_KEY}}'
      ]
    end

    def parse_aichat_models(response_body, error_text, status, api_key)
      response, error = parse_aichat_response(response_body, error_text, status, api_key)
      return [nil, error] unless error.nil?

      data = response['data']
      return [nil, 'OpenAI model response did not contain data.'] unless data.is_a?(Array)

      models = []
      data.each do |item|
        next unless item.is_a?(Hash)

        model = item['id']
        next unless model.is_a?(String) && !model.empty?
        next unless model =~ /\Agpt-5(?:$|[.-])/

        models << model unless models.include?(model)
      end
      return [nil, 'OpenAI model response did not contain model IDs.'] if models.empty?

      [models.sort, nil]
    end

    def start_aichat_request(api_prompt, conversation_prompt, waiting_start = nil,
                             waiting_end = nil, preserve_input = false)
      target_buffer = @current_buffer
      target_window = @frame.edit_win
      if waiting_start.nil? || waiting_end.nil?
        waiting_start, waiting_end = append_aichat_waiting
      end
      @ext.data['aichat']['request_running'] = true
      request_aichat(api_prompt) do |answer, error|
        append_aichat_conversation_turn(conversation_prompt, answer) unless answer.nil?
        finish_aichat_request(
          target_buffer,
          target_window,
          waiting_start,
          waiting_end,
          answer || error,
          preserve_input
        )
      end
    end

    def request_aichat(prompt, &completion)
      ensure_aichat_model
      api_key = ENV['OPENAI_API_KEY']
      if api_key.nil? || api_key.empty?
        completion.call(nil, 'OPENAI_API_KEY is not set.')
        return
      end

      tools = build_aichat_tools
      request_aichat_step(build_aichat_input(prompt), nil, tools, 0, api_key, &completion)
    rescue StandardError => e
      completion.call(nil, redact_aichat_secret(e.to_s, api_key))
    end

    def request_aichat_step(input, previous_response_id, tools, tool_call_count, api_key,
                            request_instructions = nil, &completion)
      request = {
        'model' => @ext.data['aichat']['model'],
        'input' => input
      }
      if tools.empty?
        request['instructions'] = request_instructions unless request_instructions.nil?
      else
        request['tools'] = tools
        request['parallel_tool_calls'] = false
        request['instructions'] = request_instructions || AichatExtension::AGENT_INSTRUCTIONS
      end
      request['previous_response_id'] = previous_response_id unless previous_response_id.nil?

      arguments = aichat_curl_arguments
      @ext.data['aichat']['runner'].call(arguments, JSON.generate(request)) do |response_body,
                                                                               error_text,
                                                                               status|
        response, error = parse_aichat_response(response_body, error_text, status, api_key)
        unless error.nil?
          completion.call(nil, error)
          next
        end

        tool_calls = extract_aichat_tool_calls(response)
        if tool_calls.empty?
          output = extract_aichat_output_text(response)
          if output.empty?
            completion.call(nil, 'OpenAI response did not contain output text.')
          else
            completion.call(output, nil)
          end
          next
        end

        if tool_calls.length > 1
          completion.call(nil, 'OpenAI returned multiple tool calls; parallel tool calls are unsupported.')
          next
        end
        if tool_call_count >= AichatExtension::MAX_AGENT_TOOL_CALLS
          finalize_aichat_tool_limit(
            response,
            tool_calls[0],
            tool_call_count,
            api_key,
            &completion
          )
          next
        end

        continue_aichat_tool_call(
          response,
          tool_calls[0],
          tools,
          tool_call_count,
          api_key,
          &completion
        )
      rescue StandardError => e
        completion.call(nil, redact_aichat_secret(e.to_s, api_key))
      end
    rescue StandardError => e
      completion.call(nil, redact_aichat_secret(e.to_s, api_key))
    end

    def aichat_curl_arguments
      [
        '--disable',
        '--silent',
        '--show-error',
        '--fail-with-body',
        '--connect-timeout', AichatExtension::CONNECT_TIMEOUT_SECONDS.to_s,
        '--max-time', AichatExtension::REQUEST_TIMEOUT_SECONDS.to_s,
        '--request', 'POST',
        '--url', AichatExtension::RESPONSES_URL,
        '--variable', '%OPENAI_API_KEY',
        '--expand-header', 'Authorization: Bearer {{OPENAI_API_KEY}}',
        '--header', 'Content-Type: application/json',
        '--data-binary', '@-'
      ]
    end

    def build_aichat_tools
      return [] unless respond_to?(:agent_tools) && respond_to?(:agent_call_tool)

      agent_tools.map do |tool|
        {
          'type' => 'function',
          'name' => tool['name'],
          'description' => tool['description'],
          'parameters' => tool['input_schema'],
          'strict' => true
        }
      end
    end

    def parse_aichat_response(response_body, error_text, status, api_key)
      log_aichat_failure(status, error_text, api_key) unless status == 0
      response = JSON.parse(response_body)
      if response['error'].is_a?(Hash)
        return [nil, redact_aichat_secret(response['error']['message'].to_s, api_key)]
      end
      return [nil, "curl exited with status #{status}"] unless status == 0

      [response, nil]
    rescue JSON::ParserError
      log_aichat_parse_failure
      [nil, status == 0 ? 'OpenAI returned invalid JSON.' : "curl exited with status #{status}"]
    rescue StandardError => e
      [nil, redact_aichat_secret(e.to_s, api_key)]
    end

    def extract_aichat_tool_calls(response)
      output = response['output']
      return [] unless output.is_a?(Array)

      output.select { |item| item.is_a?(Hash) && item['type'] == 'function_call' }
    end

    def continue_aichat_tool_call(response, tool_call, tools, tool_call_count, api_key,
                                  &completion)
      response_id = response['id']
      call_id = tool_call['call_id']
      if response_id.nil? || response_id.empty? || call_id.nil? || call_id.empty?
        completion.call(nil, 'OpenAI tool call did not contain required IDs.')
        return
      end
      unless respond_to?(:agent_tools) && respond_to?(:agent_call_tool)
        completion.call(nil, 'AI agent tools are not available.')
        return
      end

      arguments = JSON.parse(tool_call['arguments'].to_s)
      unless arguments.is_a?(Hash)
        completion.call(nil, 'OpenAI tool call arguments must be a JSON object.')
        return
      end
      tool_name = tool_call['name'].to_s
      call_number = tool_call_count + 1
      @logger.debug(
        "[aichat] tool call #{call_number}/#{AichatExtension::MAX_AGENT_TOOL_CALLS}: #{tool_name}"
      )
      begin
        result = agent_call_tool(tool_name, arguments)
      rescue StandardError => e
        continue_aichat_tool_error(
          response_id,
          call_id,
          tool_name,
          arguments,
          e,
          tools,
          tool_call_count,
          api_key,
          &completion
        )
        return
      end
      result_summary = result.is_a?(Array) ? "matches=#{result.length}" : 'completed'
      @logger.debug "[aichat] tool result: #{tool_name} #{result_summary}"
      tool_output = {
        'type' => 'function_call_output',
        'call_id' => call_id,
        'output' => JSON.generate(result)
      }
      request_aichat_step(
        [tool_output],
        response_id,
        tools,
        tool_call_count + 1,
        api_key,
        &completion
      )
    rescue JSON::ParserError
      completion.call(nil, 'OpenAI tool call arguments contained invalid JSON.')
    rescue StandardError => e
      completion.call(nil, redact_aichat_secret(e.to_s, api_key))
    end

    def continue_aichat_tool_error(response_id, call_id, tool_name, arguments, error, tools,
                                   tool_call_count, api_key, &completion)
      message = redact_aichat_secret(error.to_s, api_key)
      @logger.debug "[aichat] tool error: #{tool_name}: #{message}"
      tool_output = {
        'type' => 'function_call_output',
        'call_id' => call_id,
        'output' => JSON.generate(
          {
            'error' => 'tool_execution_failed',
            'tool' => tool_name,
            'arguments' => arguments,
            'message' => message,
            'suggestion' => 'Correct the arguments or use another tool based on this error.'
          }
        )
      }
      request_aichat_step(
        [tool_output],
        response_id,
        tools,
        tool_call_count + 1,
        api_key,
        &completion
      )
    end

    def finalize_aichat_tool_limit(response, tool_call, tool_call_count, api_key, &completion)
      response_id = response['id']
      call_id = tool_call['call_id']
      if response_id.nil? || response_id.empty? || call_id.nil? || call_id.empty?
        completion.call(nil, 'OpenAI tool call did not contain required IDs.')
        return
      end

      tool_name = tool_call['name'].to_s
      @logger.debug(
        "[aichat] tool call limit reached; not executed: #{tool_name}"
      )
      tool_output = {
        'type' => 'function_call_output',
        'call_id' => call_id,
        'output' => JSON.generate(
          {
            'error' => 'tool_call_limit_reached',
            'message' => "The tool was not executed because the limit of #{tool_call_count} " \
                         'successful tool calls was reached.',
            'requested_tool' => tool_name
          }
        )
      }
      request_aichat_step(
        [tool_output],
        response_id,
        [],
        tool_call_count,
        api_key,
        aichat_tool_limit_instructions,
        &completion
      )
    rescue StandardError => e
      completion.call(nil, redact_aichat_secret(e.to_s, api_key))
    end

    def aichat_tool_limit_instructions
      [
        'The tool call limit has been reached. Do not request additional tools.',
        'Provide a best-effort answer using only facts already established by successful tool results.',
        'Clearly distinguish:',
        '- facts confirmed by tool results;',
        '- facts that remain unverified;',
        '- the additional fact or narrower follow-up question needed to continue.',
        'Do not invent missing information. Do not respond only with a tool-limit error.'
      ].join("\n")
    end

    def extract_aichat_output_text(response)
      texts = []
      output = response['output']
      output = [] unless output.is_a?(Array)

      output.each do |item|
        next unless item['type'] == 'message'

        content_items = item['content']
        content_items = [] unless content_items.is_a?(Array)

        content_items.each do |content|
          texts << content['text'].to_s if content['type'] == 'output_text'
        end
      end
      texts.join
    end

    def redact_aichat_secret(message_text, api_key)
      return message_text if api_key.nil? || api_key.empty?

      message_text.gsub(api_key, '[REDACTED]')
    end

    def log_aichat_failure(status, error_text, api_key)
      @logger.info "[aichat] curl exited with status #{status}"
      unless error_text.nil? || error_text.empty?
        @logger.info "[aichat] curl stderr: #{redact_aichat_secret(error_text, api_key)}"
      end
    end

    def log_aichat_parse_failure
      @logger.info '[aichat] failed to parse response JSON'
    end

    def build_aichat_input(prompt)
      input = []
      @ext.data['aichat']['conversation'].each do |message|
        input << {
          'role' => message['role'].to_s,
          'content' => message['content'].to_s
        }
      end
      input << { 'role' => 'user', 'content' => prompt }
      input
    end

    def append_aichat_conversation_turn(user_text, assistant_text)
      conversation = @ext.data['aichat']['conversation']
      conversation << { 'role' => 'user', 'content' => user_text.dup }
      conversation << { 'role' => 'assistant', 'content' => assistant_text.dup }

      message_limit = AichatExtension::CONVERSATION_TURN_LIMIT * 2
      while conversation.length > message_limit
        conversation.shift
        conversation.shift
      end
    end

    def reset_aichat_buffer
      view = @frame.view_win
      view.sci_set_text('You: ')
      view.sci_goto_pos(view.sci_get_length)
      @ext.data['aichat']['input_start'] = view.sci_get_current_pos
      @current_buffer.docpointer = view.sci_get_docpointer
    end

    def append_aichat_waiting
      view = @frame.view_win
      start_position = view.sci_get_length
      view.sci_insert_text(start_position, AichatExtension::WAITING_TEXT)
      view.sci_goto_pos(view.sci_get_length)
      [start_position, view.sci_get_length]
    end

    def append_aichat_ask(instruction)
      view = @frame.view_win
      input_start = @ext.data['aichat']['input_start']
      draft = if input_start.nil?
                ''
              else
                view.sci_get_text_range(input_start, view.sci_get_length)
              end

      if draft.empty?
        view.sci_insert_text(view.sci_get_length, instruction)
        view.sci_goto_pos(view.sci_get_length)
        waiting_start, waiting_end = append_aichat_waiting
        return [waiting_start, waiting_end, false]
      end

      insert_position = input_start - 'You: '.bytesize
      question = "You: #{instruction}#{AichatExtension::WAITING_TEXT}\n\n"
      waiting_start = insert_position + "You: #{instruction}".bytesize
      waiting_end = waiting_start + AichatExtension::WAITING_TEXT.bytesize
      view.sci_insert_text(insert_position, question)
      @ext.data['aichat']['input_start'] = input_start + question.bytesize
      view.sci_goto_pos(view.sci_get_length)
      [waiting_start, waiting_end, true]
    end

    def finish_aichat_request(target_buffer, target_window, waiting_start, waiting_end, text,
                              preserve_input = false)
      @ext.data['aichat']['request_running'] = false
      response = {
        'text' => text,
        'waiting_start' => waiting_start,
        'waiting_end' => waiting_end,
        'preserve_input' => preserve_input
      }
      if @current_buffer.equal?(target_buffer) && @frame.edit_win.equal?(target_window)
        apply_aichat_response(@frame.view_win, response)
      else
        @ext.data['aichat']['pending_response'] = response
      end
    end

    def apply_pending_aichat_response
      response = @ext.data['aichat']['pending_response']
      return if response.nil?

      @ext.data['aichat']['pending_response'] = nil
      apply_aichat_response(@frame.view_win, response)
    end

    def apply_aichat_response(view, response)
      waiting_start = response['waiting_start']
      waiting_end = response['waiting_end']
      waiting_text = view.sci_get_text_range(waiting_start, waiting_end)
      preserve_input = response['preserve_input'] == true
      replacement = "\nAssistant: #{response['text']}"
      replacement += "\n\nYou: " unless preserve_input
      answer_start = nil
      if waiting_text == AichatExtension::WAITING_TEXT
        view.sci_set_target_start(waiting_start)
        view.sci_set_target_end(waiting_end)
        view.sci_replace_target(replacement.bytesize, replacement)
        answer_start = waiting_start + "\nAssistant: ".bytesize
        if preserve_input
          difference = replacement.bytesize - (waiting_end - waiting_start)
          @ext.data['aichat']['input_start'] += difference
        end
      elsif preserve_input
        input_start = @ext.data['aichat']['input_start']
        insert_position = input_start - 'You: '.bytesize
        fallback = "Assistant: #{response['text']}\n\n"
        view.sci_insert_text(insert_position, fallback)
        answer_start = insert_position + 'Assistant: '.bytesize
        @ext.data['aichat']['input_start'] = input_start + fallback.bytesize
      else
        insert_position = view.sci_get_length
        view.sci_insert_text(insert_position, replacement)
        answer_start = insert_position + "\nAssistant: ".bytesize
      end
      unless preserve_input
        @ext.data['aichat']['input_start'] = view.sci_get_length
      end
      view.sci_goto_pos(answer_start)
      view.sci_scroll_caret
    end
  end
end
