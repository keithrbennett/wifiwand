# frozen_string_literal: true

module WifiWand
  class ReplContext
    REPL_ONLY_METHODS = [].freeze

    def initialize(cli)
      @cli = cli
    end

    def avail_nets(*args) = dispatch('avail_nets', *args)
    alias a avail_nets

    def ci(*args) = dispatch('ci', *args)

    def connect(*args) = dispatch('connect', *args)
    alias co connect

    def cycle(*args) = dispatch('cycle', *args)
    alias cy cycle

    def disconnect(*args) = dispatch('disconnect', *args)
    alias d disconnect

    def forget(*args) = dispatch('forget', *args)
    alias f forget

    def help(*args) = dispatch('help', *args)
    alias h help

    def info(*args) = dispatch('info', *args)
    alias i info

    def log(*args) = dispatch('log', *args)
    alias lo log

    def nameservers(*args) = dispatch('nameservers', *args)
    alias na nameservers

    def network_name(*args) = dispatch('network_name', *args)
    alias ne network_name

    def off(*args) = dispatch('off', *args)
    alias of off

    def on(*args) = dispatch('on', *args)

    def password(*args) = dispatch('password', *args)
    alias pa password

    def pref_nets(*args) = dispatch('pref_nets', *args)
    alias pr pref_nets

    def public_ip(*args) = dispatch('public_ip', *args)
    alias pi public_ip

    def qr(*args) = dispatch('qr', *args)

    def quit(*args) = dispatch('quit', *args)
    alias q quit
    alias x quit
    alias xit quit

    def random_mac(*args) = dispatch('random_mac', *args)
    alias rmac random_mac

    def ropen(*args) = dispatch('ropen', *args)
    alias ro ropen

    def shell(*args) = dispatch('shell', *args)
    alias sh shell

    def status(*args) = dispatch('status', *args)
    alias s status

    def till(*args) = dispatch('till', *args)
    alias t till

    def url(*args) = dispatch('url', *args)
    alias u url

    def wifi_on(*args) = dispatch('wifi_on', *args)
    alias w wifi_on

    private def dispatch(command_name, *args)
      @cli.resolve_command(command_name)&.call(*args)
    end
  end
end
