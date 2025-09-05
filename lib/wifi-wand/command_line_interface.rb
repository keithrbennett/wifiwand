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

    model_options = OpenStruct.new({
      verbose:        options.verbose,
      wifi_interface: options.wifi_interface
    })

    @model = OperatingSystems.create_model_for_current_os(model_options)
    @interactive_mode = !!(options.interactive_mode)
    run_shell if @interactive_mode
  end

  def verbose_mode
    options.verbose
  end

  # Asserts that a command has been passed on the command line.
  def validate_command_line
    if ARGV.empty?
      puts "Syntax is: #{File.basename($0)} [options] command [command_options]. #{help_hint}"
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
          Available networks, in descending signal strength order, 
          and not including any currently connected network, are:
  
          #{format_object(info)}" "
        MESSAGE
      else
        "Wifi is off, cannot see available networks."
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
      puts "Using saved password for '#{network}'. Use 'forget #{network}' if you need to use a different password."
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
          current_nameservers_as_string = current_nameservers.empty? ? "[None]" : current_nameservers.join(', ')
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
      <<~MESSAGE
        Preferred network "#{network}" {
          password ? "stored password is \"#{password}\"." : "has no stored password."
        }
      MESSAGE
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
    target_status = options[0].to_sym
    wait_interval_in_secs = (options[1] ? Float(options[1]) : nil)
    model.till(target_status, wait_interval_in_secs)
  end

  def cmd_w
    on = model.wifi_on?
    handle_output(on, -> { "Wifi on: #{on}" })
  end

  def cmd_qr
    filename = model.generate_qr_code
    handle_output(filename, -> { "QR code generated: #{filename}" })
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
    status_data = model.status_line_data
    handle_output(status_data, -> { status_line(status_data) })
    status_data
  end

  def cmd_x
    quit
  end

  # Use macOS 'open' command line utility
  def cmd_ro(*resource_codes)
    if resource_codes.empty?
      puts model.available_resources_help
      return
    end

    result = model.open_resources_by_codes(*resource_codes)
    
    unless result[:invalid_codes].empty?
      puts model.resource_manager.invalid_codes_error(result[:invalid_codes])
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
    rescue WifiWand::BadCommandError => error
      puts error.to_s
      puts help_hint
      exit(-1)
    end
  end

  private

  def handle_output(data, human_readable_string_producer)
    if interactive_mode
      data
    else
      if options.post_processor
        puts options.post_processor.(data)
      else
        puts human_readable_string_producer.call
      end
    end
  end
end
end
