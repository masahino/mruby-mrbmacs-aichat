module Mrbmacs
  module Command
    def aichat
      buffer_name = AichatExtension::AICHAT_BUFFER_NAME
      existing_buffer = Mrbmacs.get_buffer_from_name(@buffer_list, buffer_name)
      setup_result_buffer(buffer_name)
      unless existing_buffer.nil?
        apply_pending_aichat_response
        return
      end

      @frame.view_win.sci_insert_text(0, 'You: ')
      @frame.view_win.sci_goto_pos(@frame.view_win.sci_get_length)
      @ext.data['aichat']['input_start'] = @frame.view_win.sci_get_current_pos
      @current_buffer.docpointer = @frame.view_win.sci_get_docpointer
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

      start_aichat_request(prompt)
    end

    def aichat_ask
      if @ext.data['aichat']['request_running']
        message 'AI Chat request is already running'
        return
      end

      source_view = @frame.view_win
      selection_start = source_view.sci_get_selection_start
      selection_end = source_view.sci_get_selection_end
      source = if selection_start == selection_end
                 source_view.sci_get_text(source_view.sci_get_length + 1)
               else
                 source_view.sci_get_text_range(selection_start, selection_end)
               end
      source = source.dup

      instruction = @frame.echo_gets('AI: ')
      return if instruction.nil? || instruction.strip.empty?

      api_prompt = "Instruction:\n#{instruction}\n\nSource:\n#{source}"
      aichat
      waiting_start, waiting_end, preserve_input = append_aichat_ask(instruction)
      start_aichat_request(api_prompt, waiting_start, waiting_end, preserve_input)
    end

    private

    def start_aichat_request(prompt, waiting_start = nil, waiting_end = nil, preserve_input = false)
      target_buffer = @current_buffer
      target_window = @frame.edit_win
      if waiting_start.nil? || waiting_end.nil?
        waiting_start, waiting_end = append_aichat_waiting
      end
      @ext.data['aichat']['request_running'] = true
      request_aichat(prompt) do |answer, error|
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
      api_key = ENV['OPENAI_API_KEY']
      if api_key.nil? || api_key.empty?
        completion.call(nil, 'OPENAI_API_KEY is not set.')
        return
      end

      model = ENV['MRBMACS_AICHAT_MODEL']
      model = AichatExtension::DEFAULT_MODEL if model.nil? || model.empty?
      request_body = JSON.generate('model' => model, 'input' => prompt)
      arguments = [
        '--silent',
        '--show-error',
        '--fail-with-body',
        '--request', 'POST',
        '--url', AichatExtension::RESPONSES_URL,
        '--header', "Authorization: Bearer #{api_key}",
        '--header', 'Content-Type: application/json',
        '--data-binary', '@-'
      ]

      @ext.data['aichat']['runner'].call(arguments, request_body) do |response_body, error_text, status|
        answer, error = process_aichat_result(response_body, error_text, status, api_key)
        completion.call(answer, error)
      end
    rescue StandardError => e
      completion.call(nil, redact_aichat_secret(e.to_s, api_key))
    end

    def process_aichat_result(response_body, error_text, status, api_key)
      log_aichat_failure(status, error_text, response_body, api_key) unless status == 0
      response = JSON.parse(response_body)
      if response['error'].is_a?(Hash)
        return [nil, redact_aichat_secret(response['error']['message'].to_s, api_key)]
      end
      return [nil, "curl exited with status #{status}"] unless status == 0

      output = extract_aichat_output_text(response)
      return [nil, 'OpenAI response did not contain output text.'] if output.empty?

      [output, nil]
    rescue JSON::ParserError
      log_aichat_parse_failure(response_body, api_key)
      [nil, status == 0 ? 'OpenAI returned invalid JSON.' : "curl exited with status #{status}"]
    rescue StandardError => e
      [nil, redact_aichat_secret(e.to_s, api_key)]
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

    def log_aichat_failure(status, error_text, response_body, api_key)
      @logger.info "[aichat] curl exited with status #{status}"
      unless error_text.nil? || error_text.empty?
        @logger.info "[aichat] curl stderr: #{redact_aichat_secret(error_text, api_key)}"
      end
      unless response_body.nil? || response_body.empty?
        @logger.info "[aichat] response body: #{redact_aichat_secret(response_body, api_key)}"
      end
    end

    def log_aichat_parse_failure(response_body, api_key)
      body = response_body.to_s
      @logger.info '[aichat] failed to parse response JSON'
      @logger.info "[aichat] response body: #{redact_aichat_secret(body, api_key)}" unless body.empty?
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
      if waiting_text == AichatExtension::WAITING_TEXT
        view.sci_set_target_start(waiting_start)
        view.sci_set_target_end(waiting_end)
        view.sci_replace_target(replacement.bytesize, replacement)
        if preserve_input
          difference = replacement.bytesize - (waiting_end - waiting_start)
          @ext.data['aichat']['input_start'] += difference
        end
      elsif preserve_input
        input_start = @ext.data['aichat']['input_start']
        insert_position = input_start - 'You: '.bytesize
        fallback = "Assistant: #{response['text']}\n\n"
        view.sci_insert_text(insert_position, fallback)
        @ext.data['aichat']['input_start'] = input_start + fallback.bytesize
      else
        view.sci_insert_text(view.sci_get_length, replacement)
      end
      view.sci_goto_pos(view.sci_get_length)
      unless preserve_input
        @ext.data['aichat']['input_start'] = view.sci_get_current_pos
      end
    end
  end
end
