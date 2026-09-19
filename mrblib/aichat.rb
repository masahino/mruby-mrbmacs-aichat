module Mrbmacs
  class AichatExtension < Extension
    AICHAT_BUFFER_NAME = '*AI Chat*'.freeze
    DEFAULT_MODEL = 'gpt-5.6-luna'.freeze
    AICHAT_MODELS = [
      'gpt-5.6-luna',
      'gpt-5.6-terra',
      'gpt-5.6-sol'
    ].freeze
    MODELS_URL = 'https://api.openai.com/v1/models'.freeze
    RESPONSES_URL = 'https://api.openai.com/v1/responses'.freeze
    WAITING_TEXT = "\nAssistant: Waiting for response...".freeze
    CONNECT_TIMEOUT_SECONDS = 10
    REQUEST_TIMEOUT_SECONDS = 300
    CONVERSATION_TURN_LIMIT = 10
    MAX_EDITOR_CONTEXT_BYTES = 64 * 1024
    MAX_AGENT_TOOL_CALLS = 5
    BASE_INSTRUCTIONS = [
      'You are an AI assistant integrated into the mrbmacs editor.',
      'When relevant, use the editor capabilities available to you.',
      'Do not assume editor capabilities that are not available.'
    ].join("\n").freeze
    AGENT_INSTRUCTIONS = [
      "Use the minimum number of tool calls needed to answer the user's request.",
      'Before each tool call, determine what fact is still missing.',
      'Prefer the tool that directly provides that fact.',
      'Do not use another tool merely to confirm information already established by a ' \
      'successful tool result.',
      'Use additional tools only when they provide information necessary for the requested answer.',
      'Stop using tools as soon as the requested facts are established.'
    ].join("\n").freeze

    def self.register_aichat(appl)
      Mrbmacs::ModeManager.add_mode(AICHAT_BUFFER_NAME, 'aichat')
      unless appl.effective_keybindings.key?('C-c a')
        appl.modify_keymap('C-c a', 'aichat')
      end
      unless appl.effective_keybindings.key?('C-c C-a')
        appl.modify_keymap('C-c C-a', 'aichat_ask')
      end
      appl.ext.data['aichat'] = {
        'input_start' => nil,
        'request_running' => false,
        'pending_response' => nil,
        'conversation' => [],
        'target_buffer' => nil,
        'model' => nil,
        'models' => AICHAT_MODELS.dup,
        'runner' => lambda do |arguments, request_body, &completion|
          start_curl(appl, arguments, request_body, &completion)
        end
      }
      appl.add_command_event(:after_kill_buffer) do |app, buffer|
        state = app.ext.data['aichat']
        next unless state['target_buffer'].equal?(buffer)

        state['target_buffer'] = nil
        app.send(:update_aichat_modeline)
      end
    end

    def self.start_curl(appl, arguments, request_body, &completion)
      curl_io = nil
      error_reader = nil
      error_writer = nil
      request = nil

      error_reader, error_writer = IO.pipe
      command = (['curl'] + arguments).map { |argument| shell_quote(argument) }.join(' ')
      curl_io = IO.popen(command, 'r+', err: error_writer.fileno)
      error_writer.close
      curl_io.write(request_body)
      curl_io.close_write

      request = {
        'stdout' => '',
        'stderr' => '',
        'stdout_closed' => false,
        'stderr_closed' => false,
        'stdout_io' => curl_io,
        'stderr_io' => error_reader,
        'stdout_registered' => false,
        'stderr_registered' => false,
        'completed' => false,
        'completion' => completion
      }
      watch_curl_io(appl, request, 'stdout', curl_io)
      watch_curl_io(appl, request, 'stderr', error_reader)
    rescue StandardError => e
      cleanup_curl_events(appl, request) unless request.nil?
      error_writer.close unless error_writer.nil? || error_writer.closed?
      error_reader.close unless error_reader.nil? || error_reader.closed?
      curl_io.close unless curl_io.nil? || curl_io.closed?
      error_text = e.to_s
      completion.call('', error_text, 1)
    end

    def self.shell_quote(argument)
      "'#{argument.to_s.gsub("'") { %q('"'"') }}'"
    end

    def self.watch_curl_io(appl, request, stream, io)
      request["#{stream}_registered"] = true
      appl.add_io_read_event(io) do |app, readable_io|
        begin
          request[stream] << readable_io.sysread(4096)
        rescue EOFError
          close_curl_stream(app, request, stream, readable_io)
        rescue StandardError => e
          request['stderr'] << e.to_s
          close_curl_stream(app, request, stream, readable_io)
        end
      end
    end

    def self.close_curl_stream(appl, request, stream, io)
      begin
        appl.del_io_read_event(io)
      rescue StandardError => e
        request['stderr'] << e.to_s
      end
      request["#{stream}_registered"] = false
      io.close if stream == 'stderr' && !io.closed?
      request["#{stream}_closed"] = true
      complete_curl(request) if request['stdout_closed'] && request['stderr_closed']
    end

    def self.complete_curl(request)
      return if request['completed']

      request['completed'] = true
      status = 1
      begin
        stdout_io = request['stdout_io']
        stdout_io.close unless stdout_io.nil? || stdout_io.closed?
        process_status = $?
        status = process_status.respond_to?(:exitstatus) ? process_status.exitstatus : process_status
        status = 1 if status.nil?
      rescue StandardError => e
        request['stderr'] << e.to_s
      end
      request['completion'].call(request['stdout'], request['stderr'], status)
    end

    def self.cleanup_curl_events(appl, request)
      %w[stdout stderr].each do |stream|
        next unless request["#{stream}_registered"]

        io = request["#{stream}_io"]
        begin
          appl.del_io_read_event(io)
        rescue StandardError
          io.close unless io.nil? || io.closed?
        end
        request["#{stream}_registered"] = false
      end
      %w[stderr stdout].each do |stream|
        io = request["#{stream}_io"]
        io.close unless io.nil? || io.closed?
      end
    end
  end
end
