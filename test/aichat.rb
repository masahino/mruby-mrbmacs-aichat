def aichat_success_response(text)
  JSON.generate(
    'output' => [
      {
        'type' => 'message',
        'content' => [{ 'type' => 'output_text', 'text' => text }]
      }
    ]
  )
end

def aichat_tool_call_response(response_id, call_id, name, arguments)
  JSON.generate(
    'id' => response_id,
    'output' => [
      {
        'type' => 'function_call',
        'call_id' => call_id,
        'name' => name,
        'arguments' => arguments
      }
    ]
  )
end

def aichat_models_response(*models)
  JSON.generate('data' => models.map { |model| { 'id' => model } })
end

assert('AichatExtension registers its runner') do
  app = Mrbmacs::AichatTestSupport::App.new

  assert_true app.ext.data['aichat']['runner'].respond_to?(:call)
end

assert('AichatExtension registers C-c C-a globally without changing C-c C-c') do
  app = Mrbmacs::AichatTestSupport::App.new

  assert_false app.current_buffer.name == Mrbmacs::AichatExtension::AICHAT_BUFFER_NAME
  assert_equal 'aichat_ask', app.effective_keybindings['C-c C-a']
  assert_equal 'aichat_ask', app.global_keybindings['C-c C-a']
  assert_equal 'compile', app.global_keybindings['C-c C-c']
end

assert('AichatMode keeps C-c C-c and inherits global C-c C-a') do
  app = Mrbmacs::AichatTestSupport::App.new

  app.aichat

  assert_equal 'aichat_ask', app.effective_keybindings['C-c C-a']
  assert_equal 'aichat_send', app.effective_keybindings['C-c C-c']
end

assert('AichatExtension does not overwrite an existing C-c C-a binding') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.modify_keymap('C-c C-a', 'existing_command')

  Mrbmacs::AichatExtension.register_aichat(app)

  assert_equal 'existing_command', app.global_keybindings['C-c C-a']
end

assert('aichat_ask is available as an extended command') do
  assert_true Mrbmacs::Command.instance_methods.include?(:aichat_ask)
end

assert('aichat_clear is available as an extended command') do
  assert_true Mrbmacs::Command.instance_methods.include?(:aichat_clear)
end

assert('aichat_model is available as an extended command') do
  assert_true Mrbmacs::Command.instance_methods.include?(:aichat_model)
end

assert('AichatExtension registers *AI Chat* mode') do
  Mrbmacs::AichatTestSupport::App.new

  mode = Mrbmacs::ModeManager.set_mode_by_filename('*AI Chat*')
  assert_equal 'aichat', mode.name
  assert_equal Mrbmacs::MARKDOWN_LEXER_PROFILE, mode.lexer_profile
  assert_equal 'markdown', mode.lexer
  assert_equal 'aichat_send', mode.keymap['C-c C-c']
  assert_false mode.keymap.key?('C-c C-a')
end

assert('AichatMode applies the Markdown lexer without changing normal modes') do
  view = Mrbmacs::AichatTestSupport::View.new
  aichat_mode = Mrbmacs::AichatMode.new
  fundamental_mode = Mrbmacs::FundamentalMode.new

  aichat_mode.apply_lexer(view)

  assert_equal 'markdown', view.lexer_language
  assert_equal Mrbmacs::FUNDAMENTAL_LEXER_PROFILE, fundamental_mode.lexer_profile
end

assert('aichat creates and initializes *AI Chat*') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_model = ENV['MRBMACS_AICHAT_MODEL']
  ENV['MRBMACS_AICHAT_MODEL'] = nil

  app.aichat

  assert_equal ['*AI Chat*'], app.setup_result_buffer_calls
  assert_equal '*AI Chat*', app.current_buffer.name
  assert_equal 'You: ', app.frame.view_win.text
  assert_equal 5, app.frame.view_win.position
  assert_equal 5, app.ext.data['aichat']['input_start']
  assert_equal Mrbmacs::AichatExtension::DEFAULT_MODEL, app.ext.data['aichat']['model']
  assert_equal Mrbmacs::AichatExtension::DEFAULT_MODEL, app.current_buffer.additional_info
  assert_equal [Mrbmacs::AichatExtension::DEFAULT_MODEL], app.frame.modeline_values
ensure
  ENV['MRBMACS_AICHAT_MODEL'] = old_model
end

assert('aichat initializes its model from the environment only once') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_model = ENV['MRBMACS_AICHAT_MODEL']
  ENV['MRBMACS_AICHAT_MODEL'] = 'environment-model'

  app.aichat
  assert_equal 'environment-model', app.ext.data['aichat']['model']

  ENV['MRBMACS_AICHAT_MODEL'] = 'changed-environment-model'
  app.aichat
  assert_equal 'environment-model', app.ext.data['aichat']['model']
  assert_equal 'environment-model', app.current_buffer.additional_info
ensure
  ENV['MRBMACS_AICHAT_MODEL'] = old_model
end

assert('aichat_model completes and selects a fixed model') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_model = ENV['MRBMACS_AICHAT_MODEL']
  old_key = ENV['OPENAI_API_KEY']
  ENV['MRBMACS_AICHAT_MODEL'] = nil
  ENV['OPENAI_API_KEY'] = nil
  app.aichat
  app.ext.data['aichat']['conversation'] = [
    { 'role' => 'user', 'content' => 'old question' },
    { 'role' => 'assistant', 'content' => 'old answer' }
  ]
  conversation = app.ext.data['aichat']['conversation']
  app.frame.queue_echo_input('gpt-5.6-terra')

  app.aichat_model

  assert_equal ['AI model: '], app.frame.echo_prompts
  assert_equal [Mrbmacs::AichatExtension::DEFAULT_MODEL], app.frame.echo_defaults
  assert_equal 'gpt-5.6-terra', app.ext.data['aichat']['model']
  assert_equal 'gpt-5.6-terra', app.current_buffer.additional_info
  assert_equal conversation, app.ext.data['aichat']['conversation']
  assert_equal ['gpt-5.6-terra', 'gpt-5.6-terra'.length],
               app.frame.completion_results.last
  assert_equal 'gpt-5.6-terra', app.frame.modeline_values.last
ensure
  ENV['MRBMACS_AICHAT_MODEL'] = old_model
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_model exposes all matching fixed models to completion') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = nil
  app.frame.queue_echo_input('gpt-5.6-')

  app.aichat_model

  assert_equal [Mrbmacs::AichatExtension::AICHAT_MODELS.join(' '), 'gpt-5.6-'.length],
               app.frame.completion_results.last
  assert_equal ["Unknown AI model: gpt-5.6-"], app.messages
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_model replaces fixed choices with models returned by the API') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'secret'
  arguments = nil
  body = nil
  app.ext.data['aichat']['runner'] = lambda do |curl_arguments, request_body, &completion|
    arguments = curl_arguments
    body = request_body
    completion.call(
      aichat_models_response(
        'gpt-5-z',
        'gpt-5.1',
        'chatgpt-image-latest',
        'gpt-image-1',
        'gpt-4o'
      ),
      '',
      0
    )
  end
  app.frame.queue_echo_input('gpt-5-z')

  app.aichat_model

  assert_true arguments.include?('GET')
  assert_true arguments.include?(Mrbmacs::AichatExtension::MODELS_URL)
  assert_false arguments.join(' ').include?('secret')
  assert_equal '', body
  assert_equal ['gpt-5-z', 'gpt-5.1'], app.ext.data['aichat']['models']
  assert_equal 'gpt-5-z', app.ext.data['aichat']['model']
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_model keeps cached choices when the models API fails') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'secret'
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completion.call('{"error":{"message":"unavailable"}}', '', 22)
  end
  app.frame.queue_echo_input(Mrbmacs::AichatExtension::DEFAULT_MODEL)

  app.aichat_model

  assert_equal Mrbmacs::AichatExtension::AICHAT_MODELS,
               app.ext.data['aichat']['models']
  assert_true app.messages.include?('Could not refresh AI models: unavailable')
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_model keeps the current model for cancellation, empty, and unknown input') do
  app = Mrbmacs::AichatTestSupport::App.new
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = nil
  app.aichat
  current_model = app.ext.data['aichat']['model']

  app.frame.queue_echo_input(nil)
  app.aichat_model
  app.frame.queue_echo_input('')
  app.aichat_model
  app.frame.queue_echo_input('not-a-model')
  app.aichat_model

  assert_equal current_model, app.ext.data['aichat']['model']
  assert_equal ['Unknown AI model: not-a-model'], app.messages
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_model is rejected while a request is running') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.ext.data['aichat']['request_running'] = true

  app.aichat_model

  assert_equal ['AI Chat request is already running'], app.messages
  assert_equal [], app.frame.echo_prompts
  assert_nil app.ext.data['aichat']['model']
end

assert('aichat displays an existing *AI Chat* without clearing it') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer("You: first\nAssistant: answer\n\nYou: ")
  original_text = app.frame.view_win.text

  app.aichat

  assert_equal original_text, app.frame.view_win.text
end

assert('aichat_send only runs in *AI Chat*') do
  app = Mrbmacs::AichatTestSupport::App.new
  called = false
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &_completion|
    called = true
  end

  app.aichat_send

  assert_false called
  assert_equal ['aichat-send is only available in *AI Chat*'], app.messages
end

assert('aichat_send does not run for an empty prompt') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: ', 'You: ')
  called = false
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &_completion|
    called = true
  end

  app.aichat_send

  assert_false called
end

assert('aichat_send does not run before the current input start') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.frame.view_win.position = 0
  called = false
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &_completion|
    called = true
  end

  app.aichat_send

  assert_false called
end

assert('aichat_send sends only the current multiline prompt and appends the answer') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer(
    "You: old\nAssistant: old answer\n\nYou: first line\nsecond line",
    'second line'
  )
  request_arguments = nil
  request_body = nil
  old_key = ENV['OPENAI_API_KEY']
  old_model = ENV['MRBMACS_AICHAT_MODEL']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  ENV['MRBMACS_AICHAT_MODEL'] = 'test-model'
  app.ext.data['aichat']['runner'] = lambda do |arguments, body, &completion|
    request_arguments = arguments
    request_body = body
    completion.call(aichat_success_response('new answer'), '', 0)
  end

  app.aichat_send

  request = JSON.parse(request_body)
  assert_equal 1, request['input'].length
  assert_equal 'user', request['input'][0]['role']
  assert_equal "first line\nsecond line", request['input'][0]['content']
  assert_equal 'test-model', request['model']
  assert_false request.key?('tools')
  assert_false request.key?('parallel_tool_calls')
  assert_equal '--disable', request_arguments[0]
  assert_true request_arguments.include?('%OPENAI_API_KEY')
  assert_true request_arguments.include?('Authorization: Bearer {{OPENAI_API_KEY}}')
  assert_false request_arguments.join.include?('test-secret')
  assert_true request_arguments.include?('--connect-timeout')
  assert_true request_arguments.include?('--max-time')
  assert_true request_arguments.include?('@-')
  assert_equal "You: old\nAssistant: old answer\n\nYou: first line\nsecond line\nAssistant: new answer\n\nYou: ",
               app.frame.view_win.text
  assert_equal app.frame.view_win.text.index('new answer'), app.frame.view_win.position
  assert_equal app.frame.view_win.text.bytesize, app.ext.data['aichat']['input_start']
  assert_false app.frame.view_win.position == app.ext.data['aichat']['input_start']
  assert_equal 1, app.frame.view_win.scroll_caret_calls
  assert_equal [
    { 'role' => 'user', 'content' => "first line\nsecond line" },
    { 'role' => 'assistant', 'content' => 'new answer' }
  ], app.ext.data['aichat']['conversation']
ensure
  ENV['OPENAI_API_KEY'] = old_key
  ENV['MRBMACS_AICHAT_MODEL'] = old_model
end

assert('aichat executes search_project and sends its result before displaying the final answer') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: Find target_word', 'You: Find target_word')
  app.define_singleton_method(:agent_tools) do
    [{
      'name' => 'search_project',
      'description' => 'Search the current project for a literal string.',
      'input_schema' => {
        'type' => 'object',
        'properties' => { 'query' => { 'type' => 'string' } },
        'required' => ['query'],
        'additionalProperties' => false
      }
    }]
  end
  tool_calls = []
  app.define_singleton_method(:agent_call_tool) do |name, arguments|
    tool_calls << [name, arguments]
    [{ 'file' => '/project/file.rb', 'line' => 7, 'text' => 'target_word' }]
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  requests = []
  running_states = []
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    requests << JSON.parse(body)
    running_states << app.ext.data['aichat']['request_running']
    if requests.length == 1
      completion.call(
        aichat_tool_call_response(
          'resp_1',
          'call_1',
          'search_project',
          JSON.generate('query' => 'target_word')
        ),
        '',
        0
      )
    else
      completion.call(aichat_success_response('Found it.'), '', 0)
    end
  end

  app.aichat_send

  assert_equal 2, requests.length
  assert_equal [true, true], running_states
  assert_equal [{ 'query' => 'target_word' }], tool_calls.map { |call| call[1] }
  assert_equal 'search_project', tool_calls[0][0]
  assert_equal false, requests[0]['parallel_tool_calls']
  assert_equal [{
    'type' => 'function',
    'name' => 'search_project',
    'description' => 'Search the current project for a literal string.',
    'parameters' => {
      'type' => 'object',
      'properties' => { 'query' => { 'type' => 'string' } },
      'required' => ['query'],
      'additionalProperties' => false
    },
    'strict' => true
  }], requests[0]['tools']
  assert_equal 'resp_1', requests[1]['previous_response_id']
  assert_equal 'function_call_output', requests[1]['input'][0]['type']
  assert_equal 'call_1', requests[1]['input'][0]['call_id']
  assert_equal [
    { 'file' => '/project/file.rb', 'line' => 7, 'text' => 'target_word' }
  ], JSON.parse(requests[1]['input'][0]['output'])
  assert_true app.frame.view_win.text.include?('Assistant: Found it.')
  assert_equal [
    { 'role' => 'user', 'content' => 'Find target_word' },
    { 'role' => 'assistant', 'content' => 'Found it.' }
  ], app.ext.data['aichat']['conversation']
  assert_equal [
    '[aichat] tool call 1/5: search_project',
    '[aichat] tool result: search_project matches=1'
  ], app.logger.debug_messages
  assert_false app.logger.debug_messages.join.include?('target_word')
  assert_false app.logger.debug_messages.join.include?('/project/file.rb')
  assert_false app.ext.data['aichat']['conversation'].to_s.include?('/project/file.rb')
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat reports a tool call when agent integration is unavailable') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completion.call(
      aichat_tool_call_response('resp_1', 'call_1', 'search_project', '{"query":"foo"}'),
      '', 0
    )
  end

  app.aichat_send

  assert_true app.frame.view_win.text.include?('AI agent tools are not available.')
  assert_equal [], app.ext.data['aichat']['conversation']
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat supports sequential search_project calls') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: Compare foo and bar', 'You: Compare foo and bar')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  queries = []
  app.define_singleton_method(:agent_call_tool) do |_name, arguments|
    queries << arguments['query']
    []
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  requests = []
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    requests << JSON.parse(body)
    case requests.length
    when 1
      completion.call(
        aichat_tool_call_response('resp_1', 'call_1', 'search_project', '{"query":"foo"}'),
        '', 0
      )
    when 2
      completion.call(
        aichat_tool_call_response('resp_2', 'call_2', 'search_project', '{"query":"bar"}'),
        '', 0
      )
    else
      completion.call(aichat_success_response('Compared.'), '', 0)
    end
  end

  app.aichat_send

  assert_equal ['foo', 'bar'], queries
  assert_equal 3, requests.length
  assert_equal 'resp_1', requests[1]['previous_response_id']
  assert_equal 'resp_2', requests[2]['previous_response_id']
  assert_true app.frame.view_win.text.include?('Assistant: Compared.')
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat reports invalid tool arguments without running the tool') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  called = false
  app.define_singleton_method(:agent_call_tool) do |_name, _arguments|
    called = true
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completion.call(
      aichat_tool_call_response('resp_1', 'call_1', 'search_project', 'not json'),
      '', 0
    )
  end

  app.aichat_send

  assert_false called
  assert_true app.frame.view_win.text.include?('OpenAI tool call arguments contained invalid JSON.')
  assert_equal [], app.ext.data['aichat']['conversation']
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat reports agent tool errors') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  app.define_singleton_method(:agent_call_tool) do |_name, _arguments|
    raise ArgumentError, 'Project is not available'
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completion.call(
      aichat_tool_call_response('resp_1', 'call_1', 'search_project', '{"query":"foo"}'),
      '', 0
    )
  end

  app.aichat_send

  assert_true app.frame.view_win.text.include?('Project is not available')
  assert_equal [], app.ext.data['aichat']['conversation']
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat passes an unknown tool name to the agent interface and reports its error') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  received_name = nil
  app.define_singleton_method(:agent_call_tool) do |name, _arguments|
    received_name = name
    raise ArgumentError, "Unknown agent tool: #{name}"
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completion.call(
      aichat_tool_call_response('resp_1', 'call_1', 'unknown', '{}'),
      '', 0
    )
  end

  app.aichat_send

  assert_equal 'unknown', received_name
  assert_true app.frame.view_win.text.include?('Unknown agent tool: unknown')
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat keeps an agent final response pending after switching windows') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  app.define_singleton_method(:agent_call_tool) do |_name, _arguments|
    []
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  completions = []
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    completions << completion
  end

  app.aichat_send
  completions[0].call(
    aichat_tool_call_response('resp_1', 'call_1', 'search_project', '{"query":"foo"}'),
    '', 0
  )
  app.frame.edit_win = Object.new
  completions[1].call(aichat_success_response('final answer'), '', 0)

  assert_false app.frame.view_win.text.include?('final answer')
  assert_equal 'final answer', app.ext.data['aichat']['pending_response']['text']
  assert_false app.ext.data['aichat']['request_running']

  app.aichat

  assert_true app.frame.view_win.text.include?('Assistant: final answer')
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat reports an HTTP error while sending a tool result') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  app.define_singleton_method(:agent_call_tool) do |_name, _arguments|
    []
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  requests = 0
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    requests += 1
    if requests == 1
      completion.call(
        aichat_tool_call_response('resp_1', 'call_1', 'search_project', '{"query":"foo"}'),
        '', 0
      )
    else
      completion.call('', 'curl failed', 7)
    end
  end

  app.aichat_send

  assert_equal 2, requests
  assert_true app.frame.view_win.text.include?('curl exited with status 7')
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat stops before executing a sixth agent tool call') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  app.define_singleton_method(:agent_tools) do
    [{ 'name' => 'search_project', 'description' => 'Search', 'input_schema' => {} }]
  end
  executed = 0
  app.define_singleton_method(:agent_call_tool) do |_name, _arguments|
    executed += 1
    []
  end
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  responses = 0
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
    responses += 1
    completion.call(
      aichat_tool_call_response(
        "resp_#{responses}",
        "call_#{responses}",
        'search_project',
        '{"query":"foo"}'
      ),
      '',
      0
    )
  end

  app.aichat_send

  assert_equal 5, executed
  assert_equal 6, responses
  assert_true app.frame.view_win.text.include?('AI Chat tool call limit reached.')
  assert_false app.ext.data['aichat']['request_running']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_send does not run curl without an API key') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = nil
  called = false
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &_completion|
    called = true
  end

  app.aichat_send

  assert_false called
  assert_true app.frame.view_win.text.include?('OPENAI_API_KEY is not set.')
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_send reports curl, API, and JSON errors without exposing the key') do
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'

  cases = [
    [['', 'curl failed', 7], 'curl exited with status 7'],
    [[JSON.generate('error' => { 'message' => 'bad test-secret' }), 'HTTP error', 22], 'bad [REDACTED]'],
    [['not json', '', 0], 'OpenAI returned invalid JSON.']
  ]
  cases.each do |runner_result, expected|
    app = Mrbmacs::AichatTestSupport::App.new
    app.use_aichat_buffer('You: question', 'You: question')
    app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &completion|
      completion.call(*runner_result)
    end

    app.aichat_send

    assert_true app.frame.view_win.text.include?(expected)
    assert_false app.frame.view_win.text.include?('test-secret')
    assert_false app.logger.messages.join.include?('test-secret')
    response_body = runner_result[0]
    assert_false app.logger.messages.join.include?(response_body) unless response_body.empty?
    assert_equal [], app.ext.data['aichat']['conversation']
    assert_equal app.frame.view_win.text.index(expected), app.frame.view_win.position
    assert_equal 1, app.frame.view_win.scroll_caret_calls
  end
ensure
  ENV['OPENAI_API_KEY'] = old_key
end


assert('aichat_send shows waiting text and prevents a second request') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  completion = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &callback|
    completion = callback
  end

  app.aichat_send
  app.aichat_send

  assert_true app.frame.view_win.text.end_with?(Mrbmacs::AichatExtension::WAITING_TEXT)
  assert_equal ['AI Chat request is already running'], app.messages
  completion.call(aichat_success_response('answer'), '', 0)
  assert_true app.frame.view_win.text.end_with?("Assistant: answer\n\nYou: ")
  assert_equal app.frame.view_win.text.index('answer'), app.frame.view_win.position
  assert_equal app.frame.view_win.text.bytesize, app.ext.data['aichat']['input_start']
  assert_equal 1, app.frame.view_win.scroll_caret_calls
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat completion appends when waiting text was edited') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  completion = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &callback|
    completion = callback
  end

  app.aichat_send
  app.frame.view_win.text.sub!('Waiting', 'Changed')
  completion.call(aichat_success_response('answer'), '', 0)

  assert_true app.frame.view_win.text.include?('Assistant: Changed for response...')
  assert_true app.frame.view_win.text.end_with?("Assistant: answer\n\nYou: ")
  assert_equal app.frame.view_win.text.rindex('answer'), app.frame.view_win.position
  assert_equal app.frame.view_win.text.bytesize, app.ext.data['aichat']['input_start']
  assert_equal 1, app.frame.view_win.scroll_caret_calls
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat completion is pending after switching windows') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  completion = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &callback|
    completion = callback
  end

  app.aichat_send
  app.frame.edit_win = Object.new
  completion.call(aichat_success_response('answer'), '', 0)
  assert_false app.frame.view_win.text.include?('Assistant: answer')

  app.aichat
  assert_true app.frame.view_win.text.end_with?("Assistant: answer\n\nYou: ")
  assert_equal app.frame.view_win.text.index('answer'), app.frame.view_win.position
  assert_equal app.frame.view_win.text.bytesize, app.ext.data['aichat']['input_start']
  assert_equal 1, app.frame.view_win.scroll_caret_calls
ensure
  ENV['OPENAI_API_KEY'] = old_key
end


assert('aichat_ask does not request when echo input is cancelled') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_edit_buffer('source')
  app.frame.queue_echo_input(nil)
  called = false
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &_completion|
    called = true
  end

  app.aichat_ask

  assert_false called
  assert_equal 'source', app.frame.view_win.text
end

assert('aichat_ask sends the selected region and displays only the instruction') do
  app = Mrbmacs::AichatTestSupport::App.new
  source_buffer = app.current_buffer
  app.use_edit_buffer('before selected after', 7, 15)
  app.frame.queue_echo_input('Explain this')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request_body = nil
  completion = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &callback|
    request_body = body
    completion = callback
  end

  app.aichat_ask

  assert_equal ['AI about region: '], app.frame.echo_prompts
  request = JSON.parse(request_body)
  assert_equal 1, request['input'].length
  assert_equal 'user', request['input'][0]['role']
  assert_equal "User instruction:\nExplain this\n\n" \
               "Editor context for this request:\nselected",
               request['input'][0]['content']
  assert_equal "You: Explain this\nAssistant: Waiting for response...", app.frame.view_win.text
  assert_false app.frame.view_win.text.include?('selected')
  assert_equal 'before selected after', app.buffer_text(source_buffer.name)

  completion.call(aichat_success_response('answer'), '', 0)
  assert_equal "You: Explain this\nAssistant: answer\n\nYou: ", app.frame.view_win.text
  assert_equal app.frame.view_win.text.index('answer'), app.frame.view_win.position
  assert_equal app.frame.view_win.text.bytesize, app.ext.data['aichat']['input_start']
  assert_equal 1, app.frame.view_win.scroll_caret_calls
  assert_equal [
    { 'role' => 'user', 'content' => 'Explain this' },
    { 'role' => 'assistant', 'content' => 'answer' }
  ], app.ext.data['aichat']['conversation']
  assert_false app.ext.data['aichat']['conversation'].to_s.include?('selected')
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_ask sends the whole buffer when there is no region') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_edit_buffer("first\nsecond", 3, 3)
  app.frame.queue_echo_input('Review')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request_body = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    request_body = body
    completion.call(aichat_success_response('done'), '', 0)
  end

  app.aichat_ask

  assert_equal ['AI about whole buffer: '], app.frame.echo_prompts
  request = JSON.parse(request_body)
  assert_equal "User instruction:\nReview\n\n" \
               "Editor context for this request:\nfirst\nsecond",
               request['input'][0]['content']
  assert_false app.frame.view_win.text.include?('first')
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_ask preserves an existing unsent draft') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: unsent draft', 'You: unsent draft')
  app.use_edit_buffer('source')
  app.frame.queue_echo_input('Explain')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  completion = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, _body, &callback|
    completion = callback
  end

  app.aichat_ask
  assert_equal "You: Explain\nAssistant: Waiting for response...\n\nYou: unsent draft",
               app.frame.view_win.text
  draft_start = app.ext.data['aichat']['input_start']
  assert_equal 'unsent draft', app.frame.view_win.sci_get_text_range(
    draft_start,
    app.frame.view_win.sci_get_length
  )

  completion.call(aichat_success_response('answer'), '', 0)
  assert_equal "You: Explain\nAssistant: answer\n\nYou: unsent draft", app.frame.view_win.text
  draft_start = app.ext.data['aichat']['input_start']
  assert_equal 'unsent draft', app.frame.view_win.sci_get_text_range(
    draft_start,
    app.frame.view_win.sci_get_length
  )
  assert_equal app.frame.view_win.text.index('answer'), app.frame.view_win.position
  assert_false app.frame.view_win.position == draft_start
  assert_equal 1, app.frame.view_win.scroll_caret_calls
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat sends previous successful turns with the next prompt') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: first question', 'You: first question')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request_bodies = []
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    request_bodies << JSON.parse(body)
    answer = request_bodies.length == 1 ? 'first answer' : 'second answer'
    completion.call(aichat_success_response(answer), '', 0)
  end

  app.aichat_send
  app.frame.view_win.sci_insert_text(app.frame.view_win.sci_get_length, 'second question')
  app.frame.view_win.sci_goto_pos(app.frame.view_win.sci_get_length)
  app.aichat_send

  assert_equal [
    { 'role' => 'user', 'content' => 'first question' }
  ], request_bodies[0]['input']
  assert_equal [
    { 'role' => 'user', 'content' => 'first question' },
    { 'role' => 'assistant', 'content' => 'first answer' },
    { 'role' => 'user', 'content' => 'second question' }
  ], request_bodies[1]['input']
  assert_equal 4, app.ext.data['aichat']['conversation'].length
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat requests use a newly selected model and retain conversation') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: follow up', 'You: follow up')
  app.ext.data['aichat']['conversation'] = [
    { 'role' => 'user', 'content' => 'first question' },
    { 'role' => 'assistant', 'content' => 'first answer' }
  ]
  app.ext.data['aichat']['model'] = 'gpt-5.6-luna'
  app.frame.queue_echo_input('gpt-5.6-sol')
  app.aichat_model
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &_completion|
    request = JSON.parse(body)
  end

  app.aichat_send

  assert_equal 'gpt-5.6-sol', request['model']
  assert_equal 'first question', request['input'][0]['content']
  assert_equal 'first answer', request['input'][1]['content']
  assert_equal 'follow up', request['input'][2]['content']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat keeps at most ten complete conversation turns') do
  app = Mrbmacs::AichatTestSupport::App.new
  conversation = app.ext.data['aichat']['conversation']
  10.times do |index|
    conversation << { 'role' => 'user', 'content' => "user #{index}" }
    conversation << { 'role' => 'assistant', 'content' => "assistant #{index}" }
  end
  app.use_aichat_buffer('You: newest', 'You: newest')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    request = JSON.parse(body)
    completion.call(aichat_success_response('newest answer'), '', 0)
  end

  app.aichat_send

  assert_equal 21, request['input'].length
  assert_equal 20, conversation.length
  assert_equal 'user 1', conversation[0]['content']
  assert_equal 'assistant 1', conversation[1]['content']
  assert_equal 'newest', conversation[-2]['content']
  assert_equal 'newest answer', conversation[-1]['content']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_ask reuses conversation without retaining old editor context') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_edit_buffer('first private source')
  app.frame.queue_echo_input('First instruction')
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  requests = []
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &completion|
    requests << JSON.parse(body)
    completion.call(aichat_success_response('first answer'), '', 0)
  end

  app.aichat_ask
  app.use_edit_buffer('second source')
  app.frame.queue_echo_input('Follow up')
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &_completion|
    requests << JSON.parse(body)
  end
  app.aichat_ask

  second_input = requests[1]['input']
  assert_equal 'First instruction', second_input[0]['content']
  assert_equal 'first answer', second_input[1]['content']
  assert_equal 'user', second_input[2]['role']
  assert_true second_input[2]['content'].include?('Follow up')
  assert_true second_input[2]['content'].include?('second source')
  second_input.each do |message|
    assert_false message['content'].to_s.include?('first private source')
  end
  app.ext.data['aichat']['conversation'].each do |message|
    assert_false message['content'].to_s.include?('first private source')
  end
ensure
  ENV['OPENAI_API_KEY'] = old_key
end

assert('aichat_clear resets conversation, pending response, display, and input start') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer("You: old\nAssistant: answer\n\nYou: draft", 'You: draft')
  app.ext.data['aichat']['conversation'] = [
    { 'role' => 'user', 'content' => 'old' },
    { 'role' => 'assistant', 'content' => 'answer' }
  ]
  app.ext.data['aichat']['pending_response'] = { 'text' => 'pending' }
  app.ext.data['aichat']['model'] = 'gpt-5.6-sol'

  app.aichat_clear

  assert_equal [], app.ext.data['aichat']['conversation']
  assert_nil app.ext.data['aichat']['pending_response']
  assert_equal 'You: ', app.frame.view_win.text
  assert_equal 5, app.frame.view_win.position
  assert_equal 5, app.ext.data['aichat']['input_start']
  assert_equal 'gpt-5.6-sol', app.ext.data['aichat']['model']
end

assert('aichat_clear is rejected while a request is running') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: question', 'You: question')
  conversation = [{ 'role' => 'user', 'content' => 'old' }]
  pending = { 'text' => 'pending' }
  app.ext.data['aichat']['conversation'] = conversation
  app.ext.data['aichat']['pending_response'] = pending
  app.ext.data['aichat']['request_running'] = true

  app.aichat_clear

  assert_equal ['AI Chat request is already running'], app.messages
  assert_equal conversation, app.ext.data['aichat']['conversation']
  assert_equal pending, app.ext.data['aichat']['pending_response']
  assert_equal 'You: question', app.frame.view_win.text
end

assert('the first request after aichat_clear excludes old conversation') do
  app = Mrbmacs::AichatTestSupport::App.new
  app.use_aichat_buffer('You: old', 'You: old')
  app.ext.data['aichat']['conversation'] = [
    { 'role' => 'user', 'content' => 'old' },
    { 'role' => 'assistant', 'content' => 'old answer' }
  ]
  app.aichat_clear
  app.frame.view_win.sci_insert_text(app.frame.view_win.sci_get_length, 'new')
  app.frame.view_win.sci_goto_pos(app.frame.view_win.sci_get_length)
  old_key = ENV['OPENAI_API_KEY']
  ENV['OPENAI_API_KEY'] = 'test-secret'
  request = nil
  app.ext.data['aichat']['runner'] = lambda do |_arguments, body, &_completion|
    request = JSON.parse(body)
  end

  app.aichat_send

  assert_equal [{ 'role' => 'user', 'content' => 'new' }], request['input']
ensure
  ENV['OPENAI_API_KEY'] = old_key
end
