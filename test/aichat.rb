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

  app.aichat

  assert_equal ['*AI Chat*'], app.setup_result_buffer_calls
  assert_equal '*AI Chat*', app.current_buffer.name
  assert_equal 'You: ', app.frame.view_win.text
  assert_equal 5, app.frame.view_win.position
  assert_equal 5, app.ext.data['aichat']['input_start']
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
  assert_equal "first line\nsecond line", request['input']
  assert_equal 'test-model', request['model']
  assert_true request_arguments.include?('Authorization: Bearer test-secret')
  assert_equal "You: old\nAssistant: old answer\n\nYou: first line\nsecond line\nAssistant: new answer\n\nYou: ",
               app.frame.view_win.text
  assert_equal app.frame.view_win.text.bytesize, app.frame.view_win.position
  assert_equal app.frame.view_win.position, app.ext.data['aichat']['input_start']
ensure
  ENV['OPENAI_API_KEY'] = old_key
  ENV['MRBMACS_AICHAT_MODEL'] = old_model
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

  request = JSON.parse(request_body)
  assert_equal "Instruction:\nExplain this\n\nSource:\nselected", request['input']
  assert_equal "You: Explain this\nAssistant: Waiting for response...", app.frame.view_win.text
  assert_false app.frame.view_win.text.include?('selected')
  assert_equal 'before selected after', app.buffer_text(source_buffer.name)

  completion.call(aichat_success_response('answer'), '', 0)
  assert_equal "You: Explain this\nAssistant: answer\n\nYou: ", app.frame.view_win.text
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

  request = JSON.parse(request_body)
  assert_equal "Instruction:\nReview\n\nSource:\nfirst\nsecond", request['input']
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
ensure
  ENV['OPENAI_API_KEY'] = old_key
end
