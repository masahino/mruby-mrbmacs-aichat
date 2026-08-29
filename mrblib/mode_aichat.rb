module Mrbmacs
  class AichatMode < Mode
    def initialize
      super
      @name = 'aichat'
      @lexer_profile = MARKDOWN_LEXER_PROFILE
      @keymap['C-c C-c'] = 'aichat_send'
    end
  end
end
