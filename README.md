# mruby-mrbmacs-aichat

Minimal OpenAI chat support for mrbmacs.

The `*AI Chat*` buffer uses Markdown syntax highlighting.

This extension requires curl 8.3.0 or later. The API key is expanded from the
environment by curl and is not placed in curl's command-line arguments.

Set credentials and an optional model in `~/.mrbmacs`:

```ruby
ENV['OPENAI_API_KEY'] = '...'
ENV['MRBMACS_AICHAT_MODEL'] = 'gpt-5.4-mini'
```

Run `M-x aichat`, enter a question after `You: `, then run
`M-x aichat-send` or press `C-c C-c`.

Each request is independent. Previous `You:` and `Assistant:` entries shown in
`*AI Chat*` are not sent to the API as conversation history. Include any
necessary context again when asking a follow-up question.

Run `M-x aichat-ask` from an editing buffer to enter an instruction in
the echo area. The selected region is used as the source when a region is
selected; otherwise, the whole current buffer is used. The answer is shown
in `*AI Chat*` without modifying the source buffer.

The selected source is sent to the OpenAI API. If no region is selected, the
entire current buffer is sent. Do not use `aichat-ask` on buffers containing
API keys, passwords, private keys, credentials, confidential source code, or
other information that must not be sent to an external service. Select a
region when only part of a buffer should be shared.

- `C-c C-a`: Ask AI about the current region or buffer.
- `C-c C-c`: Send the prompt from `*AI Chat*`.
