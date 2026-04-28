# frozen_string_literal: true

# Manages the lifecycle of the macOS Wi-Fi helper app that runs privileged Swift code.
# The module installs, compiles, and signs the helper bundle per WifiWand version so
# network queries can bypass TCC redactions on Sonoma+ while remaining opt-in via env flag.
# Entry points:
#   * WifiWand::MacOsWifiAuthHelper.ensure_helper_installed -> installs/validates the helper bundle.
#   * Client#connected_network_name -> runs the helper's `current-network` command and returns the SSID.
#   * Client#scan_networks -> runs the helper's `scan-networks` command and returns network metadata.
#   * Client#available? -> tells callers when the helper can safely be invoked on the current host.

require 'rubygems/version'
require_relative 'mac_os_helper_artifacts'

module WifiWand
  module MacOsWifiAuthHelper
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
    # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
    MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
    # Allows power users/CI to opt out of helper usage via environment flag
    DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'
    HELPER_COMMAND_TIMEOUT_SECONDS =
      (ENV['WIFIWAND_HELPER_TIMEOUT_SECONDS'] || 3.0).to_f
    HELPER_TERMINATION_WAIT_SECONDS = 0.25
    MANIFEST_FILENAME = 'INSTALL_MANIFEST.json'

    # Returns the versioned installation directory in user's Library folder
    #
    # @return [String] absolute path to version-specific installation directory
    #   Example: ~/Library/Application Support/WifiWand/1.2.3
    module_function def versioned_install_dir = File.join(INSTALL_PARENT, helper_version)

    # Returns the path to the installed app bundle in user's Library folder
    #
    # @return [String] absolute path to the installed .app bundle
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app
    module_function def installed_bundle_path = File.join(versioned_install_dir, BUNDLE_NAME)

    # Returns the path to the compiled executable inside the installed bundle
    #
    # @return [String] absolute path to the executable binary
    #   Example: ~/Library/Application Support/WifiWand/1.2.3/wifiwand-helper.app/Contents/MacOS/wifiwand-helper
    module_function def installed_executable_path = File.join(installed_bundle_path, 'Contents', 'MacOS',
      EXECUTABLE_NAME)

    # Returns a hash containing all helper paths and version information
    #
    # @return [Hash] helper configuration with keys:
    #   - :version - helper version string
    #   - :installed_bundle - path to installed .app bundle
    #   - :installed_executable - path to compiled executable
    #   - :source_bundle - path to bundle template in gem
    module_function def helper_info
      {
        version:              helper_version,
        installed_bundle:     installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle:        source_bundle_path,
      }
    end
  end
end

require_relative 'installer'
require_relative 'client'
