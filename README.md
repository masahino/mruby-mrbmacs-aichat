# mruby-mrbmacs-aichat

Minimal OpenAI chat support for mrbmacs.

The `*AI Chat*` buffer uses Markdown syntax highlighting.

This extension requires curl 8.3.0 or later. The API key is expanded from the
environment by curl and is not placed in curl's command-line arguments.

Set credentials and an optional initial model in `~/.mrbmacs`:

```ruby
ENV['OPENAI_API_KEY'] = '...'
ENV['MRBMACS_AICHAT_MODEL'] = 'gpt-5.6-luna'
```

When `MRBMACS_AICHAT_MODEL` is not set, `gpt-5.6-luna` is used. Run
`M-x aichat-model` to change the model for the current session. The available
choices are retrieved from OpenAI's Models API when the command runs. The
browsable choices are limited to GPT-5 model IDs. The
built-in choices `gpt-5.6-luna`, `gpt-5.6-terra`, and `gpt-5.6-sol` are used as
a fallback when the model list cannot be retrieved. Changing the model
preserves the current conversation. The active model is shown in the `*AI Chat*`
mode line.

Run `M-x aichat`, enter a question after `You: `, then run
`M-x aichat-send` or press `C-c C-c`.

The most recent 10 successful conversation turns are sent to the API so that
follow-up questions can use earlier `You:` and `Assistant:` entries as context.
One turn consists of one user prompt and its successful assistant response.
Failed requests are not added to the conversation history.

Run `M-x aichat-ask` from an editing buffer to enter an instruction in
the echo area. The selected region is used as the source when a region is
selected; otherwise, the whole current buffer is used. The answer is shown
in `*AI Chat*` without modifying the source buffer.

The selected source is sent to the OpenAI API. If no region is selected, the
entire current buffer is sent. Do not use `aichat-ask` on buffers containing
API keys, passwords, private keys, credentials, confidential source code, or
other information that must not be sent to an external service. Select a
region when only part of a buffer should be shared.

Editor context supplied by `aichat-ask` is used only for that request. The
instruction and successful answer are retained as conversation history, but
the selected region or whole-buffer source is not retained or sent again with
later requests.

Run `M-x aichat-clear` to clear both the API conversation history and the
contents of `*AI Chat*`. Clearing is rejected while a request is running.
Conversation history is kept only in memory and is not saved or restored.

Previous prompts and assistant responses in the retained conversation are
sent again with later requests. Clear the conversation before starting a new
topic or when earlier content should no longer be sent to the API.

- `C-c C-a`: Ask AI about the current region or buffer.
- `C-c C-c`: Send the prompt from `*AI Chat*`.

## Optional agent tools

When `mruby-mrbmacs-agent` is included in the mrbmacs build, AI Chat exposes
its read-only `search_project` tool to the Responses API. The model may use the
tool to search the current Project while answering an existing `aichat-send`
or `aichat-ask` request. No additional command or agent mode is required.

Project search results, including matching file paths, line numbers, and line
text, are sent to the OpenAI API when the model calls the tool. AI Chat works
as before when `mruby-mrbmacs-agent` is not included.
