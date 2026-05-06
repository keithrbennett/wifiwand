# frozen_string_literal: true

require_relative 'command'

module WifiWand
  class AvailNetsCommand < Command
    command_metadata(
      short_string: 'a',
      long_string:  'avail_nets',
      description:  'list visible WiFi networks in descending signal-strength order',
      usage:        'Usage: wifi-wand avail_nets'
    )

    binds :model, output_support: :output_support

    def call
      scan = available_network_scan
      output_support.handle_output(command_data(scan), human_readable_string_producer(scan))
    end

    private def available_network_scan
      return model.available_network_scan if model.respond_to?(:available_network_scan)

      networks = model.available_network_names
      {
        'networks'          => Array(networks),
        'scan_status'       => 'ok',
        'scan_source'       => 'os',
        'ssid_data_trusted' => true,
        'warning'           => nil,
      }
    end

    private def human_readable_string_producer(scan)
      -> do
        networks = scan.fetch('networks')
        if degraded_scan?(scan)
          degraded_available_networks_message(scan)
        elsif networks.empty?
          output_support.available_networks_empty_message
        else
          available_networks_message(networks)
        end
      end
    end

    private def command_data(scan)
      if output_support.respond_to?(:cli) && output_support.cli.interactive_mode
        scan.fetch('networks')
      else
        scan
      end
    end

    private def degraded_scan?(scan) = scan.fetch('scan_status') != 'ok' || !scan.fetch('ssid_data_trusted')

    private def degraded_available_networks_message(scan)
      networks = scan.fetch('networks')
      warning = scan.fetch('warning')
      result_message = if networks.empty?
        'No trustworthy visible network names were found from fallback scan sources.'
      else
        "Fallback scan results, which may be incomplete, are:\n\n#{output_support.format_object(networks)}"
      end

      <<~MESSAGE.chomp
        Warning: #{warning}

        #{result_message}
      MESSAGE
    end

    private def available_networks_message(networks)
      <<~MESSAGE
        Available networks, in descending signal strength order,
        as returned by the OS scan, are:

        #{output_support.format_object(networks)}
      MESSAGE
    end
  end
end
