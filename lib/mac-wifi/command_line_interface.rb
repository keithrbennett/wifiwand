require_relative 'mac_os_model'

module MacWifi

class CommandLineInterface

  attr_reader :interactive_mode, :model, :open_targets, :options


  class Command < Struct.new(:min_string, :max_string, :action); end


  class OpenTarget < Struct.new(:code, :resource, :description)

    # Ex: "'ipw' (What is My IP)"
    def help_string
      "'#{code}' (#{description})"
    end
  end


  class OpenTargets < Array

    def find(code)
      detect { |target| target.code == code }
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

  OPEN_TARGETS = OpenTargets.new([
      OpenTarget.new('ipc',  'https://ipchicken.com/',     'IP Chicken'),
      OpenTarget.new('ipw',  'https://www.whatismyip.com', 'What is My IP'),
      OpenTarget.new('spe',  'http://speedtest.net/',      'Speed Test'),
      OpenTarget.new('this', 'https://github.com/keithrbennett/macwifi', 'mac-wifi Home Page'),
  ])


  # Help text to be used when requested by 'h' command, in case of unrecognized or nonexistent command, etc.
  HELP_TEXT = "
Command Line Switches:                    [mac-wifi version #{MacWifi::VERSION}]

-o[i,j,p,y]               - outputs data in inspect, JSON, puts, or YAML format when not in shell mode
-s                        - run in shell mode
-v                        - verbose mode (prints OS commands and their outputs)

Commands:

a[vail_nets]              - array of names of the available networks
ci                        - connected to Internet (not just wifi on)?
co[nnect] network-name    - turns wifi on, connects to network-name
cy[cle]                   - turns wifi off, then on, preserving network selection
d[isconnect]              - disconnects from current network, does not turn off wifi
h[elp]                    - prints this help
i[nfo]                    - a hash of wifi-related information
l[s_avail_nets]           - details about available networks
n[etwork_name]            - name (SSID) of currently connected network
on                        - turns wifi on
of[f]                     - turns wifi off
op[en]                    - open target (#{OPEN_TARGETS.help_string})
pa[ssword] network-name   - password for preferred network-name
pr[ef_nets]               - preferred (not necessarily available) networks
q[uit]                    - exits this program (interactive shell mode only) (see also 'x')
r[m_pref_nets] network-name - removes network-name from the preferred networks list
                          (can provide multiple names separated by spaces)
t[ill]                    - returns when the desired Internet connection state is true. Options:
                          1) 'on'/:on, 'off'/:off, 'conn'/:conn, or 'disc'/:disc
                          2) wait interval, in seconds (optional, defaults to 0.5 seconds)
w[ifion]                  - is the wifi on?
x[it]                     - exits this program (interactive shell mode only) (see also 'q')

When in interactive shell mode:
  * use quotes for string parameters such as method names.
  * for pry commands, use prefix `%`.

"


  def initialize(options)
    @options = options
    @model = MacOsModel.new(verbose_mode)
    @interactive_mode = !!(options.interactive_mode)
    run_shell if @interactive_mode
  end


  # Until command line option parsing is added, the only way to specify
  # verbose mode is in the environment variable MAC_WIFI_OPTS.
  def verbose_mode
    options.verbose
  end


  def print_help
    puts HELP_TEXT
  end


  # @return true if awesome_print is available (after requiring it), else false after requiring 'pp'.
  # We'd like to use awesome_print if it is available, but not require it.
  # So, we try to require it, but if that fails, we fall back to using pp (pretty print),
  # which is included in Ruby distributions without the need to install a gem.
  def awesome_print_available?
    if @awesome_print_available.nil?  # first time here
      begin
        require 'awesome_print'
        @awesome_print_available = true
      rescue LoadError
        require 'pp'
        @awesome_print_available = false
      end
    end

    @awesome_print_available
  end


  def fancy_string(object)
    awesome_print_available? ? object.ai : object.pretty_inspect
  end


  def fancy_puts(object)
    puts fancy_string(object)
  end
  alias_method :fp, :fancy_puts


  # Asserts that a command has been passed on the command line.
  def validate_command_line
    if ARGV.empty?
      puts "Syntax is: #{__FILE__} [options] command [command_options]"
      print_help
      exit(-1)
    end
  end


  # Pry will output the content of the method from which it was called.
  # This small method exists solely to reduce the amount of pry's output
  # that is not needed here.
  def run_pry
    binding.pry

    # the seemingly useless line below is needed to avoid pry's exiting
    # (see https://github.com/deivid-rodriguez/pry-byebug/issues/45)
    _a = nil
  end


  # Runs a pry session in the context of this object.
  # Commands and options specified on the command line can also be specified in the shell.
  def run_shell
    begin
      require 'pry'
    rescue LoadError
      puts "The 'pry' gem and/or one of its prerequisites, required for running the shell, was not found." +
               " Please `gem install pry` or, if necessary, `sudo gem install pry`."
      exit(-1)
    end

    print_help

    # Enable the line below if you have any problems with pry configuration being loaded
    # that is messing up this runtime use of pry:
    # Pry.config.should_load_rc = false

    # Strangely, this is the only thing I have found that successfully suppresses the
    # code context output, which is not useful here. Anyway, this will differentiate
    # a pry command from a DSL command, which _is_ useful here.
    Pry.config.command_prefix = '%'

    run_pry
  end


  # For use by the shell; when typing a command and options, it is passed to process_command_line
  def method_missing(method_name, *options)
    method_name = method_name.to_s
    method_exists = !! find_command_action(method_name)
    if method_exists
      process_command_line(method_name, options)
    else
      puts(%Q{"#{method_name}" is not a valid command or option. If you intend for this to be a string literal, use quotes or %q/Q{}.})
    end
  end


  # Processes the command (ARGV[0]) and any relevant options (ARGV[1..-1]).
  #
  # CAUTION! In interactive mode, any strings entered (e.g. a network name) MUST
  # be in a form that the Ruby interpreter will recognize as a string,
  # i.e. single or double quotes, %q, %Q, etc.
  # Otherwise it will assume it's a method name and pass it to method_missing!
  def process_command_line(command, options)
    action = find_command_action(command)
    if action
      action.(*options)
    else
      print_help
      raise BadCommandError.new(
          %Q{Unrecognized command. Command was "#{command}" and options were #{options.inspect}.})
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
        puts model.wifi_on? \
            ? "Available networks are:\n\n#{fancy_string(info)}" \
            : "Wifi is off, cannot see available networks."
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


  def cmd_lsa
    info = model.available_network_info
    if interactive_mode
      info
    else
      if post_processor
        puts post_processor.(info)
      else
        message = model.wifi_on? ? fancy_string(info) : "Wifi is off, cannot see available networks."
        puts(message)
      end
    end
  end


  def cmd_n
    name = model.current_network
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
  def cmd_op(*target_codes)
    target_codes.each do |code|
      target = OPEN_TARGETS.find(code)
      if target
        model.run_os_command("open #{target.resource}")
      end
    end
  end

  def cmd_pa(network)
    password = model.preferred_network_password(network)

    if interactive_mode
      password
    else
      if post_processor
        puts post_processor.(password)
      else
        output =  %Q{Preferred network "#{model.connected_network_name}" }
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


  def cmd_pu
    `open https://www.whatismyip.com/`
  end


  def cmd_q
    quit
  end


  def cmd_r(*options)
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
        Command.new('h',   'help',          -> (*_options) { cmd_h             }),
        Command.new('i',   'info',          -> (*_options) { cmd_i             }),
        Command.new('l',   'ls_avail_nets', -> (*_options) { cmd_lsa           }),
        Command.new('n',   'network_name',  -> (*_options) { cmd_n             }),
        Command.new('of',  'off',           -> (*_options) { cmd_of            }),
        Command.new('on',  'on',            -> (*_options) { cmd_on            }),
        Command.new('op',  'open',          -> (*options)  { cmd_op(*options)  }),
        Command.new('pa',  'password',      -> (*options)  { cmd_pa(*options)  }),
        Command.new('pr',  'pref_nets',     -> (*_options) { cmd_pr            }),
        Command.new('q',   'quit',          -> (*_options) { cmd_q             }),
        Command.new('r',   'rm_pref_nets',  -> (*options)  { cmd_r(*options)   }),
        Command.new('t',   'till',          -> (*options)  { cmd_t(*options)   }),
        Command.new('w',   'wifion',        -> (*_options) { cmd_w             }),
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
      process_command_line(ARGV[0], ARGV[1..-1])
    rescue BadCommandError => error
      separator_line = "! #{'-' * 75} !\n"
      puts '' << separator_line << error.to_s << "\n" << separator_line
      exit(-1)
    end
  end
end
end