# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'
require_relative '../timing_constants'

module WifiWand
  class TillCommand < Command
    command_metadata(
      short_string: 't',
      long_string:  'till',
      description:  'wait until a target connectivity or WiFi state is reached',
      usage:        'Usage: wifi-wand till <state> [timeout_secs] [interval_secs]'
    )

    STATES = %w[wifi_on wifi_off associated disassociated internet_on internet_off].freeze

    binds :cli, :model, :interactive_mode

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}

        States:
          wifi_on        - WiFi hardware powered on
          wifi_off       - WiFi hardware powered off
          associated     - WiFi associated with an SSID
          disassociated  - WiFi not associated with any SSID
          internet_on    - Internet connectivity state is reachable
          internet_off   - Internet connectivity state is unreachable

        Defaults:
          timeout = wait indefinitely
          interval = #{WifiWand::TimingConstants::DEFAULT_WAIT_INTERVAL}
      HELP
    end

    def call(*options)
      validate_presence!(options)
      target_status = options[0].to_sym
      timeout_in_secs = parse_timeout(options[1])
      interval_in_secs = parse_interval(options[2])

      model.till(
        target_status,
        timeout_in_secs:                         timeout_in_secs,
        wait_interval_in_secs:                   interval_in_secs,
        stringify_permitted_values_in_error_msg: !interactive_mode
      )
    end

    private def validate_presence!(options)
      return unless options.empty? || options[0].nil?

      raise WifiWand::ConfigurationError, <<~MSG.chomp
        Missing target status argument.
        Usage: till <state> [timeout_secs] [interval_secs]
        States: #{STATES.join(', ')}
        Examples: 'till wifi_off 20' or 'till internet_on 30 0.5'
        #{cli.help_hint}
      MSG
    end

    private def parse_timeout(raw_value)
      return nil if raw_value.nil?

      value = Float(raw_value)
      raise_negative_timeout(raw_value) if value < 0

      value
    rescue ArgumentError, TypeError
      raise WifiWand::ConfigurationError,
        "Invalid timeout value '#{raw_value}'. Timeout must be a number. #{cli.help_hint}"
    end

    private def raise_negative_timeout(raw_value)
      raise WifiWand::ConfigurationError,
        "Invalid timeout value '#{raw_value}'. Timeout must be non-negative. #{cli.help_hint}"
    end

    private def parse_interval(raw_value)
      return nil if raw_value.nil?

      value = Float(raw_value)
      raise_negative_interval(raw_value) if value < 0

      value
    rescue ArgumentError, TypeError
      raise WifiWand::ConfigurationError,
        "Invalid interval value '#{raw_value}'. Interval must be a number. #{cli.help_hint}"
    end

    private def raise_negative_interval(raw_value)
      raise WifiWand::ConfigurationError,
        "Invalid interval value '#{raw_value}'. Interval must be non-negative. #{cli.help_hint}"
    end
  end
end
