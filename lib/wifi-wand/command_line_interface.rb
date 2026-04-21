# frozen_string_literal: true

require 'yaml'
require 'awesome_print'
require_relative 'operating_systems'
require 'ostruct'
require_relative 'errors'
require_relative 'version'
require_relative 'timing_constants'
require_relative 'connectivity_states'

# Include extracted modules
require_relative 'command_line_interface/help_system'
require_relative 'command_line_interface/output_formatter'
require_relative 'command_line_interface/command_registry'
require_relative 'command_line_interface/shell_interface'

module WifiWand
  class CommandLineInterface
    include HelpSystem
    include OutputFormatter
    include CommandRegistry
    include ShellInterface

    attr_reader :interactive_mode, :model, :options

    PROJECT_URL = 'https://github.com/keithrbennett/wifiwand'
    SUCCESS_EXIT_CODE = 0
    FAILURE_EXIT_CODE = 1

    def initialize(options, argv: nil)
      @options = options
      parsed_argv = argv || (options.respond_to?(:argv) && options.argv)
      @argv = Array(parsed_argv).dup
      @original_out_stream = options.respond_to?(:out_stream) && options.out_stream
      @err_stream = (options.respond_to?(:err_stream) && options.err_stream) || $stderr
      @in_stream = (options.respond_to?(:in_stream) && options.in_stream) || $stdin

      model_options = {
        verbose:        options.verbose,
        wifi_interface: options.wifi_interface,
        out_stream:     out_stream,
      }

      # Skip model initialization when help was explicitly requested in non-interactive mode,
      # so that `--help` works even on systems without Wi‑Fi hardware or permissions.
      @interactive_mode = !!options.interactive_mode
      help_requested = options.respond_to?(:help_requested) && options.help_requested
      skip_model_init = help_requested && !@interactive_mode

      @model = skip_model_init ? nil : WifiWand.create_model(model_options)
    end

    def verbose_mode = options.verbose

    # Dynamic output stream that respects current $stdout (for test silence_output compatibility)
    def out_stream = @original_out_stream || $stdout

    # Asserts that a command has been passed on the command line.
    def validate_command_line(argv = @argv)
      if argv.empty?
        @err_stream.puts "Syntax is: #{File.basename($PROGRAM_NAME)} [options] command [command_options]. " \
          "#{help_hint}"
        return FAILURE_EXIT_CODE
      end

      SUCCESS_EXIT_CODE
    end

    # Processes the command (ARGV[0]) and any relevant options (ARGV[1..-1]).
    #
    # CAUTION! In interactive mode, any strings entered (e.g. a network name) MUST
    # be in a form that the Ruby interpreter will recognize as a string,
    # i.e. single or double quotes, %q, %Q, etc.
    # Otherwise it will assume it's a method name and pass it to method_missing!
    def process_command_line(argv = @argv)
      attempt_command_action(argv[0], *argv[1..]) do
        raise WifiWand::BadCommandError,
          "Unrecognized command. Command was #{argv.first.inspect} and options were #{argv[1..].inspect}."
      end
    end

    # ===== MODEL-RELATED COMMANDS =====
    # All commands that delegate to the model stay here

    def cmd_a
      build_avail_nets_command.call
    end

    def cmd_ci = build_ci_command.call

    def cmd_co(network, password = nil)
      build_connect_command.call(network, password)
    end

    def cmd_cy = build_cycle_command.call

    def cmd_d = build_disconnect_command.call

    def cmd_i = build_info_command.call

    def cmd_public_ip(selector = 'both')
      build_public_ip_command.call(selector)
    end

    # Performs nameserver functionality.
    # @param subcommand 'get' or no arg to get, 'clear' to clear, and an array of IP addresses to set
    def cmd_na(*)
      build_nameservers_command.call(*)
    end

    def cmd_ne
      build_network_name_command.call
    end

    def cmd_of = build_off_command.call

    def cmd_on = build_on_command.call

    def cmd_pa(network)
      build_password_command.call(network)
    end

    def cmd_pr
      build_pref_nets_command.call
    end

    def cmd_f(*)
      build_forget_command.call(*)
    end

    def cmd_t(*options)
      build_till_command.call(*options)
    end

    def cmd_w = build_wifi_on_command.call

    def cmd_qr(filespec = nil, password = nil)
      # Normalize destination and determine if stdout ('-') is requested
      spec = filespec.nil? ? nil : filespec.to_s
      to_stdout = (spec == '-')

      if to_stdout
        # Interactive shell returns the ANSI string (so users can `puts(qr :-)`),
        # while non-interactive prints ANSI to stdout and returns nil for CLI UX.
        # In shell, we return the string; non-interactive prints and returns nil
        result = model.generate_qr_code('-', delivery_mode: (interactive_mode ? :return : :print),
          password: password)
        interactive_mode ? result : nil
      else
        result = model.generate_qr_code(filespec, password: password)
        handle_output(result, -> { "QR code generated: #{result}" })
      end
    rescue WifiWand::Error => e
      if e.message.include?('already exists') && @in_stream.tty?
        out_stream.print 'Output file exists. Overwrite? [y/N]: '
        answer = @in_stream.gets&.strip&.downcase
        if %w[y yes].include?(answer)
          result = model.generate_qr_code(filespec, overwrite: true, password: password)
          handle_output(result, -> { "QR code generated: #{result}" })
        else
          # user declined overwrite; no output
          nil
        end
      else
        raise
      end
    end

    # ===== OTHER COMMANDS =====
    # Commands that don't directly delegate to the model

    def cmd_h(command_name = nil)
      build_help_command.call(command_name)
    end

    def cmd_q = quit

    def cmd_u = PROJECT_URL

    def cmd_s
      progress_mode = status_progress_mode
      # Build initial snapshot with only the fields that will actually be populated
      # Start with required fields, network_name is added by first update if model includes it
      current_snapshot = { wifi_on: nil, internet_state: ConnectivityStates::INTERNET_PENDING }
      last_visible_length = 0
      inline_progress_printed = false
      saw_progress_error = false

      progress_callback = if progress_mode == :inline
        # Stream incremental updates so DNS/TCP results surface as soon as they complete.
        ->(update) do
          if update.nil?
            saw_progress_error = true
            next
          end

          current_snapshot.merge!(update)
          rendered = status_line(current_snapshot)

          visible_length = strip_ansi(rendered).length
          padding = [last_visible_length - visible_length, 0].max
          padded_render = padding.zero? ? rendered : "#{rendered}#{' ' * padding}"

          out_stream.print("\r#{padded_render}")
          out_stream.flush if out_stream.respond_to?(:flush)

          last_visible_length = visible_length
          inline_progress_printed = true
        end
      end

      # Seed the display so users see the WAIT placeholders instantly.
      progress_callback&.call(current_snapshot.dup)

      status_data = model.status_line_data(progress_callback: progress_callback)

      if progress_mode == :inline
        if inline_progress_printed
          if saw_progress_error && status_data.nil?
            out_stream.print("\r")
            out_stream.puts status_line(nil)
          else
            out_stream.puts
          end
        else
          rendered = status_line(status_data)
          out_stream.puts(rendered) unless rendered.to_s.empty?
        end
      end

      if interactive_mode
        out_stream.puts status_line(status_data) if progress_mode == :none
        nil
      else
        return status_data unless progress_mode == :none

        handle_output(status_data, -> { status_line(status_data) })
        status_data
      end
    end

    def cmd_log(*options)
      build_log_command.call(*options)
    end

    def cmd_x = quit

    # Use macOS 'open' command line utility
    def cmd_ro(*resource_codes)
      if resource_codes.empty?
        if interactive_mode
          return model.available_resources_help
        else
          out_stream.puts model.available_resources_help
        end

        return
      end

      result = model.open_resources_by_codes(*resource_codes)

      unless result[:invalid_codes].empty?
        @err_stream.puts model.resource_manager.invalid_codes_error(result[:invalid_codes])
      end

      nil
    end

    # ===== MAIN ENTRY POINT =====

    def call
      return run_shell if interactive_mode

      validation_status = validate_command_line
      return validation_status unless validation_status == SUCCESS_EXIT_CODE

      begin
        # By this time, the Main class has removed the command line options, and all that is left
        # in argv is the command and its options.
        process_command_line
        SUCCESS_EXIT_CODE
      rescue WifiWand::Error => e
        @err_stream.puts(verbose_mode && e.respond_to?(:to_h) ? YAML.dump(e.to_h) : e.to_s)
        @err_stream.puts help_hint unless e.message.include?(help_hint)
        FAILURE_EXIT_CODE
      end
    end

    private def status_progress_mode
      return :none if options.post_processor

      return :none unless out_stream.respond_to?(:tty?) && out_stream.tty?

      :inline
    end

    # Strips ANSI escape codes from a string so we can measure visible length
    # when padding inline terminal updates.
    private def strip_ansi(text) = text.to_s.gsub(/\e\[[\d;]*m/, '')

    private def build_avail_nets_command
      require_relative 'commands/avail_nets_command'
      WifiWand::AvailNetsCommand.new.bind(self)
    end

    private def build_ci_command
      require_relative 'commands/ci_command'
      WifiWand::CiCommand.new.bind(self)
    end

    private def build_connect_command
      require_relative 'commands/connect_command'
      WifiWand::ConnectCommand.new.bind(self)
    end

    private def build_cycle_command
      require_relative 'commands/cycle_command'
      WifiWand::CycleCommand.new.bind(self)
    end

    private def build_disconnect_command
      require_relative 'commands/disconnect_command'
      WifiWand::DisconnectCommand.new.bind(self)
    end

    private def build_help_command
      require_relative 'commands/help_command'
      WifiWand::HelpCommand.new.bind(self)
    end

    private def build_info_command
      require_relative 'commands/info_command'
      WifiWand::InfoCommand.new.bind(self)
    end

    private def build_nameservers_command
      require_relative 'commands/nameservers_command'
      WifiWand::NameserversCommand.new.bind(self)
    end

    private def build_network_name_command
      require_relative 'commands/network_name_command'
      WifiWand::NetworkNameCommand.new.bind(self)
    end

    private def build_log_command
      require_relative 'commands/log_command'
      WifiWand::LogCommand.new(model, output: out_stream, verbose: verbose_mode)
    end

    private def build_wifi_on_command
      require_relative 'commands/wifi_on_command'
      WifiWand::WifiOnCommand.new.bind(self)
    end

    private def build_public_ip_command
      require_relative 'commands/public_ip_command'
      WifiWand::PublicIpCommand.new.bind(self)
    end

    private def build_off_command
      require_relative 'commands/off_command'
      WifiWand::OffCommand.new.bind(self)
    end

    private def build_on_command
      require_relative 'commands/on_command'
      WifiWand::OnCommand.new.bind(self)
    end

    private def build_password_command
      require_relative 'commands/password_command'
      WifiWand::PasswordCommand.new.bind(self)
    end

    private def build_pref_nets_command
      require_relative 'commands/pref_nets_command'
      WifiWand::PrefNetsCommand.new.bind(self)
    end

    private def build_forget_command
      require_relative 'commands/forget_command'
      WifiWand::ForgetCommand.new.bind(self)
    end

    private def build_till_command
      require_relative 'commands/till_command'
      WifiWand::TillCommand.new.bind(self)
    end

    private def empty_available_networks_message
      if model.is_a?(WifiWand::MacOsModel)
        "No visible networks were found.\n" \
          'On macOS 14+, this can mean the helper could not get usable ' \
          'Location Services authorization for WiFi SSIDs.'
      elsif model.is_a?(WifiWand::UbuntuModel)
        "No visible networks were found.\n" \
          'If you expect to see networks, try running `nmcli device wifi rescan` ' \
          'or check your hardware/drivers.'
      else
        'No visible networks were found.'
      end
    end

    private def handle_output(data, human_readable_string_producer)
      if interactive_mode
        data
      else
        output = if options.post_processor
          options.post_processor.(data)
        else
          human_readable_string_producer.call
        end
        out_stream.puts output unless output.to_s.empty?
      end
    end
  end
end
