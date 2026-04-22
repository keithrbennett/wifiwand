# frozen_string_literal: true

require_relative 'command'
require_relative '../connectivity_states'

module WifiWand
  class StatusCommand < Command
    command_metadata(
      short_string: 's',
      long_string:  'status',
      description:  [
        'status line (WiFi, Network, DNS, Internet; shows captive portal warning if',
        'login is required)',
      ].join(' '),
      usage:        'Usage: wifi-wand status'
    )

    binds :cli, :model, :interactive_mode, :out_stream

    def call
      progress_mode = cli.send(:status_progress_mode)
      current_snapshot = { wifi_on: nil, internet_state: ConnectivityStates::INTERNET_PENDING }
      last_visible_length = 0
      inline_progress_printed = false
      saw_progress_error = false

      progress_callback = if progress_mode == :inline
        ->(update) do
          if update.nil?
            saw_progress_error = true
            next
          end

          current_snapshot.merge!(update)
          rendered = cli.status_line(current_snapshot)

          visible_length = cli.send(:strip_ansi, rendered).length
          padding = [last_visible_length - visible_length, 0].max
          padded_render = padding.zero? ? rendered : "#{rendered}#{' ' * padding}"

          out_stream.print("
#{padded_render}")
          out_stream.flush if out_stream.respond_to?(:flush)

          last_visible_length = visible_length
          inline_progress_printed = true
        end
      end

      progress_callback&.call(current_snapshot.dup)

      status_data = model.status_line_data(progress_callback: progress_callback)

      if progress_mode == :inline
        if inline_progress_printed
          if saw_progress_error && status_data.nil?
            out_stream.print('\r')
            out_stream.puts cli.status_line(nil)
          else
            out_stream.puts
          end
        else
          rendered = cli.status_line(status_data)
          out_stream.puts(rendered) unless rendered.to_s.empty?
        end
      end

      if interactive_mode
        out_stream.puts cli.status_line(status_data) if progress_mode == :none
        nil
      else
        return status_data unless progress_mode == :none

        cli.send(:handle_output, status_data, -> { cli.status_line(status_data) })
        status_data
      end
    end
  end
end
