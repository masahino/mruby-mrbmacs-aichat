# mruby-mrbmacs-aichat

Minimal OpenAI chat support for mrbmacs.

The `*AI Chat*` buffer uses Markdown syntax highlighting.

Set credentials and an optional model in `~/.mrbmacs`:

```ruby
ENV['OPENAI_API_KEY'] = '...'
ENV['MRBMACS_AICHAT_MODEL'] = 'gpt-5.4-mini'
```

Run `M-x aichat`, enter a question after `You: `, then run
`M-x aichat-send` or press `C-c C-c`.

Run `M-x aichat-ask` from an editing buffer to enter an instruction in
the echo area. The selected region is used as the source when a region is
selected; otherwise, the whole current buffer is used. The answer is shown
in `*AI Chat*` without modifying the source buffer.

- `C-c C-a`: Ask AI about the current region or buffer.
- `C-c C-c`: Send the prompt from `*AI Chat*`.
