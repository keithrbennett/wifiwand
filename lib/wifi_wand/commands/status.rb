# frozen_string_literal: true

require_relative 'base'
require_relative '../connectivity_states'

module WifiWand
  module Commands
    class Status < Base
      command_metadata(
        short_string: 's',
        long_string:  'status',
        description:  [
          'status line (WiFi, Network, DNS, Internet; shows captive portal warning if',
          'login is required)',
        ].join(' '),
        usage:        'Usage: wifi-wand status'
      )

      binds :model, :interactive_mode, :out_stream, output_support: :output_support

      def call(*args)
        validate_max_arguments!(args, 0)

        progress_mode = output_support.status_progress_mode
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
            rendered = output_support.status_line(current_snapshot)
            next if rendered.to_s.empty?

            visible_length = output_support.display_width(rendered)
            padding = [last_visible_length - visible_length, 0].max
            padded_render = padding.zero? ? rendered : "#{rendered}#{' ' * padding}"

            prefix = inline_progress_printed ? "\r" : ''
            out_stream.print("#{prefix}#{padded_render}")
            out_stream.flush if out_stream.respond_to?(:flush)

            last_visible_length = visible_length
            inline_progress_printed = true
          end
        end

        progress_callback&.call(current_snapshot.dup)

        status_data = model.status_line_data(progress_callback: progress_callback)

        if progress_mode == :inline
          if inline_progress_printed
            if saw_progress_error || status_data.nil?
              rendered = output_support.status_line(status_data)
              if rendered.to_s.empty?
                out_stream.puts
              else
                visible_length = output_support.display_width(rendered)
                padding = [last_visible_length - visible_length, 0].max

                out_stream.puts "\r#{rendered}#{' ' * padding}"
              end
            else
              out_stream.puts
            end
          else
            rendered = output_support.status_line(status_data)
            out_stream.puts(rendered) unless rendered.to_s.empty?
          end
        end

        if interactive_mode
          out_stream.puts output_support.status_line(status_data) if progress_mode == :none
          nil
        else
          if progress_mode == :none
            if status_data.nil?
              rendered = output_support.status_line(status_data)
              out_stream.puts(rendered) unless rendered.to_s.empty?
            else
              output_support.handle_output(status_data, -> { output_support.status_line(status_data) })
            end
          end
          raise WifiWand::StatusUnavailableError if status_data.nil?

          status_data
        end
      end
    end
  end
end
