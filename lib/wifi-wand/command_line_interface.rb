require 'awesome_print'
require_relative 'operating_systems'
require 'ostruct'
require_relative 'error'
require_relative 'version'

module WifiWand

class CommandLineInterface

  attr_reader :interactive_mode, :model, :open_resources, :options

  PROJECT_URL = 'https://github.com/keithrbennett/wifiwand'

  class Command < Struct.new(:min_string, :max_string, :action); end


  class OpenResource < Struct.new(:code, :resource, :description)

    # Ex: "'ipw' (What is My IP)"
    def help_string
      "'#{code}' (#{description})"
    end
  end


  class OpenResources < Array

    def find_by_code(code)
      detect { |resource| resource.code == code }
    end

    # Ex: "('ipc' (IP Chicken), 'ipw' (What is My IP), 'spe' (Speed Test))"
    def help_string
      map(&:help_string).join(', ')
    end
  end


  class BadCommandError < RuntimeError
    def initialize(error_message)
      super
    end
  end

  OPEN_RESOURCES = OpenResources.new([
      OpenResource.new('cap',  'https://captive.apple.com/',                'Portal Logins'),
      OpenResource.new('ipl',  'https://www.iplocation.net/',               'IP Location'),
      OpenResource.new('ipw',  'https://www.whatismyip.com',                'What is My IP'),
      OpenResource.new('libre','https://www.librespeed.org',                'LibreSpeed'),
      OpenResource.new('spe',  'http://speedtest.net/',                     'Speed Test'),
      OpenResource.new('this', 'https://github.com/keithrbennett/wifiwand', 'wifi-wand home page'),
  ])


  # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
  HELP_TEXT = "
Command Line Switches:                    [wifi-wand version #{WifiWand::VERSION} at https://github.com/keithrbennett/wifiwand]

-o {i,j,k,p,y}            - outputs data in inspect, JSON, pretty JSON, puts, or YAML format when not in shell mode
-p wifi_interface_name    - override automatic detection of interface name with this name
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:

a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
cy[cle]                   - turns wifi off, then on, preserving network selection
d[isconnect]              - disconnects from current network, does not turn off wifi
f[orget] name1 [..name_n] - removes network-name(s) from the preferred networks list
                            in interactive mode, can be a single array of names, e.g. returned by `pref_nets`
h[elp]                    - prints this help
i[nfo]                    - a hash of wifi-related information
na[meservers]             - nameservers: 'show' or no arg to show, 'clear' to clear,
                            or IP addresses to set, e.g. '9.9.9.9  8.8.8.8'
ne[twork_name]            - name (SSID) of currently connected network
on                        - turns wifi on
of[f]                     - turns wifi off
pa[ssword] network-name   - password for preferred network-name
pr[ef_nets]               - preferred (saved) networks
q[uit]                    - exits this program (interactive shell mode only) (see also 'x')
ro[pen]                   - open resource (#{OPEN_RESOURCES.help_string})
t[ill]                    - returns when the desired Internet connection state is true. Options:
                            1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                            2) wait interval between tests, in seconds (optional, defaults to 0.5 seconds)
w[ifi_on]                 - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
  * remember to quote string literals.
  * for pry commands, use prefix `%`.

"

  def initialize(options)
    current_os = OperatingSystems.new.current_os
    if current_os.nil?
      puts "This application currently runs only on Mac OS and Ubuntu Linux."
      exit(1)
    end

    @options = options

    model_options = OpenStruct.new({
      verbose:        options.verbose,
      wifi_interface: options.wifi_interface
    })

    @model = current_os.create_model(model_options)
    @interactive_mode = !!(options.interactive_mode)
    run_shell if @interactive_mode
  end


  def verbose_mode
    options.verbose
  end


  def print_help
    puts HELP_TEXT
  end


  def fancy_string(object)
    object.awesome_inspect
  end


  def fancy_puts(object)
    puts fancy_string(object)
  end
  alias_method :fp, :fancy_puts


  # Asserts that a command has been passed on the command line.
  def validate_command_line
    if ARGV.empty?
      puts "Syntax is: #{$0} [options] command [command_options]"
      print_help
      exit(-1)
    end
  end


  # Runs a pry session in the context of this object.
  # Commands and options specified on the command line can also be specified in the shell.
  def run_shell
    print_help
    require 'pry'

    # Enable the line below if you have any problems with pry configuration being loaded
    # that is messing up this runtime use of pry:
    # Pry.config.should_load_rc = false

    # Strangely, this is the only thing I have found that successfully suppresses the
    # code context output, which is not useful here. Anyway, this will differentiate
    # a pry command from a DSL command, which _is_ useful here.
    Pry.config.command_prefix = '%'

    binding.pry
  end


  # Look up the command name and, if found, run it. If not, execute the passed block.
  def attempt_command_action(command, *args, &error_handler_block)
    action = find_command_action(command)

    if action
      action.(*args)
    else
      error_handler_block.call
      nil
    end
  end


  # For use by the shell when the user types the DSL commands
  def method_missing(method_name, *method_args)
    attempt_command_action(method_name.to_s, *method_args) do
      puts(%Q{"#{method_name}" is not a valid command or option. } \
          << 'If you intend for this to be a string literal, ' \
          << 'use quotes or %q{}/%Q{}.')
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
      print_help
      raise BadCommandError.new(
          %Q{! Unrecognized command. Command was "#{ARGV.first.inspect}" and options were #{ARGV[1..-1].inspect}.})
    end
  end


  def quit
    if interactive_mode
      exit(0)
    else
      puts "This command can only be run in shell mode."
    end
  end


  def cmd_a
    info = model.available_network_names
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        message = if model.wifi_on?
          <<~MESSAGE
            Available networks, in descending signal strength order, 
            and not including any currently connected network, are:
  
            #{fancy_string(info)}"
          MESSAGE
        else
          "Wifi is off, cannot see available networks."
        end
        puts message
      end
    end
  end


  def cmd_ci
    connected = model.connected_to_internet?
    if interactive_mode
      connected
    else
      puts (post_processor ? post_processor.(connected) : "Connected to Internet: #{connected}")
    end
  end


  def cmd_co(network, password = nil)
    model.connect(network, password)
  end


  def cmd_cy
    model.cycle_network
  end


  def cmd_d
    model.disconnect
  end


  def cmd_h
    print_help
  end


  def cmd_i
    info = model.wifi_info
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        puts fancy_string(info)
      end
    end
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
        current_nameservers = model.nameservers_using_networksetup
        if interactive_mode
          current_nameservers
        else
          if post_processor
            puts post_processor.(current_nameservers)
          else
            current_nameservers_as_string = current_nameservers.empty? ? "[None]" : current_nameservers.join(', ')
            puts "Nameservers: #{current_nameservers_as_string}"
          end
        end
      when :clear
        model.set_nameservers(:clear)
      when :put
        new_nameservers = args
        model.set_nameservers(new_nameservers)
    end
  end


  def cmd_ne
    name = model.connected_network_name
    if interactive_mode
      name
    else
      display_name = name ? name : '[none]'
      puts (post_processor ? post_processor.(name) : %Q{Network (SSID) name: "#{display_name}"})
    end
  end


  def cmd_of
    model.wifi_off
  end


  def cmd_on
    model.wifi_on
  end


  # Use Mac OS 'open' command line utility
  def cmd_ro(*resource_codes)
    if resource_codes.empty?
      puts "Please specify a resource to open:\n #{OPEN_RESOURCES.help_string.gsub(',', "\n")}"
      return
    end

    resource_codes.each do |code|
      code = code.to_s  # accommodate conversion of parameter from other types, esp. symbols
      resource = OPEN_RESOURCES.find_by_code(code)
      if resource
        if code == 'spe' && Dir.exist?('/Applications/Speedtest.app/')
          model.open_application('Speedtest')
        else
          model.open_resource(resource.resource)
        end
      end
    end
    nil
  end


  def cmd_pa(network)
    password = model.preferred_network_password(network)

    if interactive_mode
      password
    else
      if post_processor
        puts post_processor.(password)
      else
        output =  %Q{Preferred network "#{network}" }
        output << (password ? %Q{stored password is "#{password}".} : "has no stored password.")
        puts output
      end
    end
  end


  def cmd_pr
    networks = model.preferred_networks
    if interactive_mode
      networks
    else
      puts (post_processor ? post_processor.(networks) : fancy_string(networks))
    end
  end


  def cmd_q
    quit
  end


  def cmd_f(*options)
    removed_networks = model.remove_preferred_networks(*options)
    if interactive_mode
      removed_networks
    else
      puts (post_processor ? post_processor.(removed_networks) : "Removed networks: #{removed_networks.inspect}")
    end
  end


  def cmd_t(*options)
    target_status = options[0].to_sym
    wait_interval_in_secs = (options[1] ? Float(options[1]) : nil)
    model.till(target_status, wait_interval_in_secs)
  end


  def cmd_w
    on = model.wifi_on?
    if interactive_mode
      on
    else
      puts (post_processor ? post_processor.(on) : "Wifi on: #{on}")
    end
  end


  def cmd_x
    quit
  end


  def commands
    @commands_ ||= [
        Command.new('a',   'avail_nets',    -> (*_options) { cmd_a             }),
        Command.new('ci',  'ci',            -> (*_options) { cmd_ci            }),
        Command.new('co',  'connect',       -> (*options)  { cmd_co(*options)  }),
        Command.new('cy',  'cycle',         -> (*_options) { cmd_cy            }),
        Command.new('d',   'disconnect',    -> (*_options) { cmd_d             }),
        Command.new('f',   'forget',        -> (*options)  { cmd_f(*options)   }),
        Command.new('h',   'help',          -> (*_options) { cmd_h             }),
        Command.new('i',   'info',          -> (*_options) { cmd_i             }),
        Command.new('l',   'ls_avail_nets', -> (*_options) { cmd_l             }),
        Command.new('na',  'nameservers',   -> (*options)  { cmd_na(*options)  }),
        Command.new('ne',  'network_name',  -> (*_options) { cmd_ne            }),
        Command.new('of',  'off',           -> (*_options) { cmd_of            }),
        Command.new('on',  'on',            -> (*_options) { cmd_on            }),
        Command.new('ro',  'ropen',         -> (*options)  { cmd_ro(*options)  }),
        Command.new('pa',  'password',      -> (*options)  { cmd_pa(*options)  }),
        Command.new('pr',  'pref_nets',     -> (*_options) { cmd_pr            }),
        Command.new('q',   'quit',          -> (*_options) { cmd_q             }),
        Command.new('t',   'till',          -> (*options)  { cmd_t(*options)   }),
        Command.new('u',   'url',           -> (*_options) { PROJECT_URL       }),
        Command.new('w',   'wifi_on',       -> (*_options) { cmd_w             }),
        Command.new('x',   'xit',           -> (*_options) { cmd_x             })
    ]
  end


  def find_command_action(command_string)
    result = commands.detect do |cmd|
      cmd.max_string.start_with?(command_string) \
      && \
      command_string.length >= cmd.min_string.length  # e.g. 'c' by itself should not work
    end
    result ? result.action : nil
  end


  # If a post-processor has been configured (e.g. YAML or JSON), use it.
  def post_process(object)
    post_processor ? post_processor.(object) : object
  end


  def post_processor
    options.post_processor
  end


  def call
    validate_command_line
    begin
      # By this time, the Main class has removed the command line options, and all that is left
      # in ARGV is the commands and their options.
      process_command_line
    rescue BadCommandError => error
      separator_line = "! #{'-' * 75} !\n"
      puts '' << separator_line << error.to_s << "\n" << separator_line
      exit(-1)
    end
  end
end
end
