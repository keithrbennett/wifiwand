# frozen_string_literal: true

require 'awesome_print'
require_relative 'operating_systems'
require 'ostruct'
require_relative 'errors'
require_relative 'version'
require_relative 'timing_constants'

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

  def initialize(options)
    @options = options
    @original_out_stream = (options.respond_to?(:out_stream) && options.out_stream)
    @err_stream = (options.respond_to?(:err_stream) && options.err_stream) || $stderr

    model_options = OpenStruct.new({
      verbose:        options.verbose,
      wifi_interface: options.wifi_interface,
      out_stream:     out_stream
    })

    # Skip model initialization when help was explicitly requested in non-interactive mode,
    # so that `--help` works even on systems without Wi‑Fi hardware or permissions.
    @interactive_mode = !!(options.interactive_mode)
    help_requested = options.respond_to?(:help_requested) && options.help_requested
    skip_model_init = help_requested && !@interactive_mode

    @model = skip_model_init ? nil : WifiWand.create_model(model_options)
    run_shell if @interactive_mode
  end

  def verbose_mode
    options.verbose
  end

  # Dynamic output stream that respects current $stdout (for test silence_output compatibility)
  def out_stream
    @original_out_stream || $stdout
  end

  # Asserts that a command has been passed on the command line.
  def validate_command_line
    if ARGV.empty?
      @err_stream.puts "Syntax is: #{File.basename($0)} [options] command [command_options]. #{help_hint}"
      exit(-1)
    end
  end

  # Processes the command (ARGV[0]) and any relevant options (ARGV[1..-1]).
  #
  # CAUTION! In interactive mode, any strings entered (e.g. a network name) MUST
  # be in a form that the Ruby interpreter will recognize as a string,
  # i.e. single or double quotes, %q, %Q, etc.
  # Otherwise it will assume it's a method name and pass it to method_missing!
  def process_command_line
    attempt_command_action(ARGV[0], *ARGV[1..-1]) do
      raise WifiWand::BadCommandError.new(
          %Q{Unrecognized command. Command was #{ARGV.first.inspect} and options were #{ARGV[1..-1].inspect}.})
    end
  end

  # ===== MODEL-RELATED COMMANDS =====
  # All commands that delegate to the model stay here

  def cmd_a
    info = model.available_network_names
    human_readable_string_producer = -> do
      if model.wifi_on?
        <<~MESSAGE
          Available networks, in descending signal strength order,#{' '}
          and not including any currently connected network, are:

          #{format_object(info)}" "
        MESSAGE
      else
        'Wifi is off, cannot see available networks.'
      end
    end
    handle_output(info, human_readable_string_producer)
  end

  def cmd_ci
    connected = model.connected_to_internet?
    handle_output(connected, -> { "Connected to Internet: #{connected}" })
  end

  def cmd_co(network, password = nil)
    model.connect(network, password)

    # Show message if we used a saved password
    if model.last_connection_used_saved_password? && !interactive_mode
      out_stream.puts "Using saved password for '#{network}'. Use 'forget #{network}' if you need to use a different password."
    end
  end

  def cmd_cy
    model.cycle_network
  end

  def cmd_d
    model.disconnect
  end

  def cmd_i
    info = model.wifi_info
    handle_output(info, -> { format_object(info) })
  end

  # Performs nameserver functionality.
  # @param subcommand 'get' or no arg to get, 'clear' to clear, and an array of IP addresses to set
  def cmd_na(*args)
    subcommand = if args.empty? || args.first.to_sym == :get
      :get
    elsif args.first.to_sym == :clear
      :clear
    else
      :put
    end

    case(subcommand)
      when :get
        current_nameservers = model.nameservers
        human_readable_string_producer = -> do
          current_nameservers_as_string = current_nameservers.empty? ? '[None]' : current_nameservers.join(', ')
          "Nameservers: #{current_nameservers_as_string}"
        end
        handle_output(current_nameservers, human_readable_string_producer)
      when :clear
        model.set_nameservers(:clear)
      when :put
        new_nameservers = args
        model.set_nameservers(new_nameservers)
    end
  end

  def cmd_ne
    name = model.connected_network_name
    handle_output(name, -> { %Q{Network (SSID) name: "#{name ? name : '[none]'}"} })
  end

  def cmd_of
    model.wifi_off
  end

  def cmd_on
    model.wifi_on
  end

  def cmd_pa(network)
    password = model.preferred_network_password(network)
    human_readable_string_producer = -> do
      %Q{Preferred network "#{network}" } +
        (password ? %Q{stored password is "#{password}".} : 'has no stored password.')
    end
    handle_output(password, human_readable_string_producer)
  end

  def cmd_pr
    networks = model.preferred_networks
    handle_output(networks, -> { format_object(networks) })
  end

  def cmd_f(*options)
    removed_networks = model.remove_preferred_networks(*options)
    handle_output(removed_networks, -> { "Removed networks: #{removed_networks.inspect}" })
  end

  def cmd_t(*options)
    # Validate that target status argument was provided
    if options.empty? || options[0].nil?
      raise WifiWand::ConfigurationError.new(
        "Missing target status argument.\n" \
        "Usage: till conn|disc|on|off [timeout_secs] [interval_secs]\n" \
        "Examples: 'till off 20' or 'till conn 30 0.5'\n" \
        "#{help_hint}"
      )
    end

    target_status = options[0].to_sym

    # Validate numeric arguments
    begin
      timeout_in_secs = (options[1] ? Float(options[1]) : nil)
    rescue ArgumentError, TypeError
      raise WifiWand::ConfigurationError.new(
        "Invalid timeout value '#{options[1]}'. Timeout must be a number. #{help_hint}"
      )
    end

    begin
      interval_in_secs = (options[2] ? Float(options[2]) : nil)
    rescue ArgumentError, TypeError
      raise WifiWand::ConfigurationError.new(
        "Invalid interval value '#{options[2]}'. Interval must be a number. #{help_hint}"
      )
    end

    # Pass CLI-friendly error formatting in non-interactive mode only.
    model.till(
      target_status,
      timeout_in_secs: timeout_in_secs,
      wait_interval_in_secs: interval_in_secs,
      stringify_permitted_values_in_error_msg: !interactive_mode
    )
  end

  def cmd_w
    on = model.wifi_on?
    handle_output(on, -> { "Wifi on: #{on}" })
  end

  def cmd_qr(filespec = nil, password = nil)
    begin
      # Normalize destination and determine if stdout ('-') is requested
      spec = filespec.nil? ? nil : filespec.to_s
      to_stdout = (spec == '-')

      if to_stdout
        # Interactive shell returns the ANSI string (so users can `puts(qr :-)`),
        # while non-interactive prints ANSI to stdout and returns nil for CLI UX.
        # In shell, we return the string; non-interactive prints and returns nil
        result = model.generate_qr_code('-', delivery_mode: (interactive_mode ? :return : :print), 
password: password)
        return interactive_mode ? result : nil
      else
        result = model.generate_qr_code(filespec, password: password)
        handle_output(result, -> { "QR code generated: #{result}" })
      end
    rescue WifiWand::Error => e
      if e.message.include?('already exists') && $stdin.tty?
        out_stream.print 'Output file exists. Overwrite? [y/N]: '
        answer = $stdin.gets&.strip&.downcase
        if ['y', 'yes'].include?(answer)
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
  end

  # ===== OTHER COMMANDS =====
  # Commands that don't directly delegate to the model

  def cmd_h
    print_help
  end

  def cmd_q
    quit
  end

  def cmd_s
    progress_mode = status_progress_mode
    # Build initial snapshot with only the fields that will actually be populated
    # Start with required fields, network_name is added by first update if model includes it
    current_snapshot = { wifi_on: nil, internet_connected: nil }
    last_visible_length = 0
    inline_progress_printed = false
    saw_progress_error = false

    progress_callback = if progress_mode == :inline
      # Stream incremental updates so DNS/TCP results surface as soon as they complete.
      lambda do |update|
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
    require_relative 'commands/log_command'
    command = WifiWand::LogCommand.new(model, output: out_stream, verbose: verbose_mode)
    command.execute(*options)
  end

  def cmd_x
    quit
  end

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
    return if interactive_mode  # Shell already ran in constructor, nothing more to do

    validate_command_line
    begin
      # By this time, the Main class has removed the command line options, and all that is left
      # in ARGV is the commands and their options.
      process_command_line
    rescue WifiWand::BadCommandError, WifiWand::ConfigurationError => error
      @err_stream.puts error.to_s
      @err_stream.puts help_hint unless error.message.include?(help_hint)
      exit(-1)
    end
  end

  private

  # Determines how the status command should present progress updates.
  # - Returns :none when output is being post-processed or the stream is non-TTY
  #   to preserve machine-readable output.
  # - Returns :inline when printing directly to an interactive terminal so we
  #   can reuse the same line with carriage returns.
  def status_progress_mode
    return :none if options.post_processor

    return :none unless out_stream.respond_to?(:tty?) && out_stream.tty?

    :inline
  end

  # Strips ANSI escape codes from a string so we can measure visible length
  # when padding inline terminal updates.
  def strip_ansi(text)
    text.to_s.gsub(/\e\[[\d;]*m/, '')
  end

  def handle_output(data, human_readable_string_producer)
    if interactive_mode
      data
    else
      if options.post_processor
        output = options.post_processor.(data)
      else
        output = human_readable_string_producer.call
      end
      out_stream.puts output unless output.to_s.empty?
    end
  end
end
end
