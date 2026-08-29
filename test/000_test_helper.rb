module Mrbmacs
  module AichatTestSupport
    class View
      attr_accessor :text, :current_line, :position, :selection_start, :selection_end
      attr_reader :lexer_language

      def initialize
        @text = ''
        @current_line = ''
        @position = 0
        @selection_start = 0
        @selection_end = 0
      end

      def sci_insert_text(position, value)
        @text = @text[0...position].to_s + value + @text[position..-1].to_s
      end

      def sci_set_text(value)
        @text = value
      end

      def sci_get_length
        @text.bytesize
      end

      def sci_goto_pos(position)
        @position = position
      end

      def sci_get_current_pos
        @position
      end

      def sci_get_selection_start
        @selection_start
      end

      def sci_get_selection_end
        @selection_end
      end

      def sci_get_text(length)
        @text.byteslice(0, length).to_s
      end

      def sci_get_text_range(start_position, end_position)
        @text[start_position...end_position].to_s
      end

      def sci_set_target_start(position)
        @target_start = position
      end

      def sci_set_target_end(position)
        @target_end = position
      end

      def sci_replace_target(_length, value)
        @text = @text[0...@target_start].to_s + value + @text[@target_end..-1].to_s
      end

      def sci_get_curline
        [@current_line, @current_line.bytesize]
      end

      def sci_get_docpointer
        1
      end

      def sci_set_lexer_language(language)
        @lexer_language = language
      end

      def sci_set_property(_property, _value)
      end

      def sci_set_keywords(_index, _keywords)
      end
    end

    class Frame
      attr_reader :view_win, :echo_prompts
      attr_accessor :edit_win

      def initialize
        @view_win = View.new
        @edit_win = Object.new
        @echo_inputs = []
        @echo_prompts = []
      end

      def queue_echo_input(input)
        @echo_inputs << input
      end

      def echo_gets(prompt, _text = '')
        @echo_prompts << prompt
        @echo_inputs.shift
      end
    end

    class App
      include Mrbmacs::Command

      attr_reader :ext, :frame, :buffer_list, :current_buffer, :messages,
                  :setup_result_buffer_calls, :logger, :global_keybindings

      def initialize
        @ext = Mrbmacs::Extension.new
        @frame = Frame.new
        @current_buffer = Mrbmacs::Buffer.new('*scratch*')
        @buffer_list = [@current_buffer]
        @messages = []
        @logger = Logger.new
        @setup_result_buffer_calls = []
        @global_keybindings = { 'C-c C-c' => 'compile' }
        @buffer_texts = { @current_buffer => '' }
        Mrbmacs::AichatExtension.register_aichat(self)
      end

      def effective_keybindings
        @global_keybindings.merge(@current_buffer.mode.keymap)
      end

      def modify_keymap(key, command)
        @global_keybindings[key] = command
      end

      def setup_result_buffer(buffer_name)
        @setup_result_buffer_calls << buffer_name
        @buffer_texts[@current_buffer] = @frame.view_win.text
        buffer = Mrbmacs.get_buffer_from_name(@buffer_list, buffer_name)
        if buffer.nil?
          buffer = Mrbmacs::Buffer.new(buffer_name)
          @buffer_list << buffer
        end
        @current_buffer = buffer
        @frame.view_win.text = @buffer_texts[buffer].to_s
        @frame.view_win.position = @frame.view_win.text.bytesize
      end

      def message(text)
        @messages << text
      end

      def use_aichat_buffer(text = '', current_line = '')
        @buffer_texts[@current_buffer] = @frame.view_win.text
        buffer = Mrbmacs::Buffer.new(Mrbmacs::AichatExtension::AICHAT_BUFFER_NAME)
        @buffer_list << buffer
        @current_buffer = buffer
        @frame.view_win.text = text
        @frame.view_win.current_line = current_line
        @frame.view_win.position = text.bytesize
        @buffer_texts[buffer] = text
        marker_position = text.rindex('You: ')
        @ext.data['aichat']['input_start'] = marker_position.nil? ? nil : marker_position + 5
      end


      def use_edit_buffer(text, selection_start = 0, selection_end = 0)
        if @current_buffer.name == Mrbmacs::AichatExtension::AICHAT_BUFFER_NAME
          @buffer_texts[@current_buffer] = @frame.view_win.text
          @current_buffer = @buffer_list.find do |buffer|
            buffer.name != Mrbmacs::AichatExtension::AICHAT_BUFFER_NAME
          end
        end
        @frame.view_win.text = text
        @frame.view_win.position = text.bytesize
        @frame.view_win.selection_start = selection_start
        @frame.view_win.selection_end = selection_end
        @buffer_texts[@current_buffer] = text
      end

      def buffer_text(buffer_name)
        buffer = Mrbmacs.get_buffer_from_name(@buffer_list, buffer_name)
        return @frame.view_win.text if buffer.equal?(@current_buffer)

        @buffer_texts[buffer]
      end
    end

    class Logger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def info(message)
        @messages << message
      end
    end
  end
end
