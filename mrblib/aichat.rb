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
    MAX_AGENT_TOOL_CALLS = 10
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
      unless appl.effective_keybindings.key?('C-c C-a')
        appl.modify_keymap('C-c C-a', 'aichat_ask')
      end
      appl.ext.data['aichat'] = {
        'input_start' => nil,
        'request_running' => false,
        'pending_response' => nil,
        'conversation' => [],
        'model' => nil,
        'models' => AICHAT_MODELS.dup,
        'runner' => lambda do |arguments, request_body, &completion|
          start_curl(appl, arguments, request_body, &completion)
        end
      }
    end

    def self.start_curl(appl, arguments, request_body, &completion)
      pid = nil
      input_reader = nil
      input_writer = nil
      output_reader = nil
      output_writer = nil
      error_reader = nil
      error_writer = nil
      request = nil

      input_reader, input_writer = IO.pipe
      output_reader, output_writer = IO.pipe
      error_reader, error_writer = IO.pipe
      pid = Process.spawn(
        'curl', *arguments,
        in: input_reader.fileno,
        out: output_writer.fileno,
        err: error_writer.fileno
      )
      input_reader.close
      output_writer.close
      error_writer.close
      input_writer.write(request_body)
      input_writer.close

      request = {
        'stdout' => '',
        'stderr' => '',
        'stdout_closed' => false,
        'stderr_closed' => false,
        'pid' => pid,
        'stdout_io' => output_reader,
        'stderr_io' => error_reader,
        'stdout_registered' => false,
        'stderr_registered' => false,
        'completed' => false,
        'completion' => completion
      }
      watch_curl_io(appl, request, 'stdout', output_reader)
      watch_curl_io(appl, request, 'stderr', error_reader)
    rescue StandardError => e
      cleanup_curl_events(appl, request) unless request.nil?
      input_reader.close unless input_reader.nil? || input_reader.closed?
      input_writer.close unless input_writer.nil? || input_writer.closed?
      output_reader.close unless output_reader.nil? || output_reader.closed?
      output_writer.close unless output_writer.nil? || output_writer.closed?
      error_reader.close unless error_reader.nil? || error_reader.closed?
      error_writer.close unless error_writer.nil? || error_writer.closed?
      error_text = e.to_s
      unless pid.nil?
        begin
          Process.waitpid(pid)
        rescue StandardError => wait_error
          error_text += "; #{wait_error}"
        end
      end
      completion.call('', error_text, 1)
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
      io.close unless io.closed?
      request["#{stream}_closed"] = true
      complete_curl(request) if request['stdout_closed'] && request['stderr_closed']
    end

    def self.complete_curl(request)
      return if request['completed']

      request['completed'] = true
      status = 1
      begin
        Process.waitpid(request['pid'])
        status = $?.exitstatus
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
    end
  end
end
