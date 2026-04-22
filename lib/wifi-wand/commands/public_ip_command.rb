# frozen_string_literal: true

require_relative 'command'
require_relative '../errors'

module WifiWand
  class PublicIpCommand < Command
    command_metadata(
      short_string: 'pi',
      long_string:  'public_ip',
      description:  'public IP lookup; selectors may use long or short form; both (b) is the default',
      usage:        'Usage: wifi-wand public_ip [address|country|both|a|c|b]'
    )

    VALID_SELECTORS = {
      'address' => 'address',
      'a'       => 'address',
      'country' => 'country',
      'c'       => 'country',
      'both'    => 'both',
      'b'       => 'both',
    }.freeze

    binds :cli, :model

    def help_text
      <<~HELP
        #{metadata.usage}

        #{metadata.description}

        Selectors:
          address (a) - return only the public IP address
          country (c) - return only the public IP country
          both (b)    - return both address and country
      HELP
    end

    def call(selector = 'both')
      normalized_selector = normalize_selector(selector)

      case normalized_selector
      when 'address'
        address = model.public_ip_address
        cli.send(:handle_output, address, -> { "Public IP Address: #{address}" })
      when 'country'
        country = model.public_ip_country
        cli.send(:handle_output, country, -> { "Public IP Country: #{country}" })
      when 'both'
        info = model.public_ip_info
        cli.send(:handle_output, info, -> {
          "Public IP Address: #{info['address']}  Country: #{info['country']}"
        })
      end
    end

    private def normalize_selector(selector)
      normalized_selector = selector.to_s.strip.downcase
      normalized_selector = 'both' if normalized_selector.empty?

      VALID_SELECTORS.fetch(normalized_selector)
    rescue KeyError
      raise WifiWand::ConfigurationError,
        "Invalid selector '#{selector}'. Use one of: address (a), country (c), both (b)."
    end
  end
end
