# frozen_string_literal: true

module WifiWand
  # Validates that subclasses of BaseModel implement every required
  # method with the correct visibility.  This module references
  # BaseModel by name and must be loaded after base_model.rb is
  # required.
  module ModelSubclassContract
    REQUIRED_SUBCLASS_METHODS = {
      _available_network_names:    :any_visibility,
      _connected_network_name:     :any_visibility,
      _connect:                    :any_visibility,
      _disconnect:                 :any_visibility,
      _ipv4_addresses:             :any_visibility,
      _ipv6_addresses:             :any_visibility,
      _preferred_network_password: :any_visibility,
      bssid:                       :public,
      connected?:                  :public,
      connection_security_type:    :public,
      default_interface:           :public,
      is_wifi_interface?:          :public,
      mac_address:                 :public,
      nameservers:                 :public,
      network_hidden?:             :public,
      open_resource:               :public,
      probe_wifi_interface:        :public,
      preferred_networks:          :public,
      remove_preferred_network:    :public,
      set_nameservers:             :public,
      signal_quality:              :public,
      validate_os_preconditions:   :public,
      wifi_off:                    :public,
      wifi_on:                     :public,
      wifi_on?:                    :public,
    }.freeze

    def self.subclass_overrides_method?(subclass, method_name)
      method = if subclass.method_defined?(method_name) || subclass.private_method_defined?(method_name)
        subclass.instance_method(method_name)
      end

      method && method.owner != BaseModel
    end

    def self.subclass_publicly_overrides_method?(subclass, method_name)
      method = if subclass.public_method_defined?(method_name)
        subclass.public_instance_method(method_name)
      end

      method && method.owner != BaseModel
    end

    def self.subclass_implements_required_method?(subclass, method_name, required_visibility)
      case required_visibility
      when :public
        subclass_publicly_overrides_method?(subclass, method_name)
      when :any_visibility
        subclass_overrides_method?(subclass, method_name)
      else
        raise ArgumentError, "Unknown required method visibility: #{required_visibility.inspect}"
      end
    end

    def self.verify_required_methods_implemented(subclass)
      missing_methods = REQUIRED_SUBCLASS_METHODS.reject do |method_name, required_visibility|
        subclass_implements_required_method?(subclass, method_name, required_visibility)
      end.keys

      unless missing_methods.empty?
        subclass_name = subclass.name || '(anonymous)'
        raise NotImplementedError, "Subclass #{subclass_name} must implement #{missing_methods.inspect}"
      end
    end

    def self.validate_subclass!(subclass)
      trace = TracePoint.new(:end) do |tp|
        if tp.self == subclass
          verify_required_methods_implemented(subclass)
          trace.disable
        end
      end
      trace.enable
    end
  end
end
