module WifiWand

  class ModelValidator

    BASE_MODEL_ESSENTIAL_METHODS = [
        :connect,
        :connected_to?,
        :connected_to_internet?,
        :cycle_network,
        :preferred_network_password,
        :public_ip_address_info,
        :random_mac_address,
        :remove_preferred_networks,
        :run_os_command,
        :till,
        :try_os_command_until,
        :verbose_mode,
        :verbose_mode=,
        :wifi_interface,
        :wifi_interface=
    ]


    BASE_MODEL_NONESSENTIAL_METHODS = [
    ]


    MAC_OS_MODEL_ESSENTIAL_METHODS = [
        :airport_command,
        :available_network_info,
        :available_network_names,
        :connected_network_name,
        :detect_wifi_interface,
        :disconnect,
        :ip_address,
        :is_wifi_interface?,
        :mac_address,
        :nameservers_using_networksetup,
        :nameservers_using_resolv_conf,
        :nameservers_using_scutil,
        :open_resource,
        :os_level_connect,
        :os_level_preferred_network_password,
        :preferred_networks,
        :remove_preferred_network,
        :set_nameservers,
        :wifi_info,
        :wifi_off,
        :wifi_on,
        :wifi_on?
    ]

    MAC_OS_MODEL_ESSENTIAL_METHODS = [
        ]

    ALL_MODEL_METHODS = BASE_MODEL_ESSENTIAL_METHODS + MAC_OS_MODEL_ESSENTIAL_METHODS


  end
end
