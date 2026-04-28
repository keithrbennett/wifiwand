# frozen_string_literal: true

# Encapsulates the business logic for checking, installing, and repairing
# the wifiwand-helper on macOS. This class is the authoritative source of
# truth for setup status; the exe/wifi-wand-macos-setup script delegates
# all decisions to it.
#
# Usage:
#   setup = WifiWand::MacOsHelperSetup.new
#   status = setup.check_status
#   status.setup_complete?     # => true/false
#   status.repair_recommended? # => true when installed but structurally broken
#   status.steps_needed        # => [:install_helper, :grant_permission] etc.
#   setup.install_helper
#   setup.reinstall_helper
#   setup.open_location_settings

require 'json'
require_relative 'mac_os_helper_bundle'

module WifiWand
  class MacOsHelperSetup
    # Immutable value object describing the current state of the helper.
    Result = Struct.new(:installed, :valid, :authorized, :permission_message, keyword_init: true) do
      def installed? = installed
      def valid?     = valid
      def authorized? = authorized

      # True only when the helper is installed, structurally valid, and
      # macOS location permission has been granted.
      def setup_complete? = installed? && valid? && authorized?

      # True when the helper is on disk but failed structural validation
      # (e.g. the bundle is corrupt or the executable does not respond to the
      # `help` command). In this case reinstall is preferable to a first-time install.
      def repair_recommended? = installed? && !valid?

      # Ordered list of symbolic steps still required.  Callers map these to
      # human-readable labels and execution logic.
      def steps_needed
        return %i[reinstall_helper grant_permission] if repair_recommended?
        return %i[install_helper grant_permission]   unless installed?
        return %i[grant_permission]                  unless authorized?

        []
      end
    end

    def initialize(out_stream: $stdout) = @out_stream = out_stream

    # Inspect the current installation and return a Result value object.
    #
    # @return [Result]
    def check_status
      helper_path = MacOsHelperBundle.installed_executable_path
      installed   = File.executable?(helper_path)
      valid       = installed && MacOsHelperBundle.helper_installed_and_valid?
      authorized, permission_message = check_authorization(helper_path, valid)

      Result.new(
        installed:          installed,
        valid:              valid,
        authorized:         authorized,
        permission_message: permission_message
      )
    end

    # Install the helper for the first time (or skip if already valid).
    # Delegates to MacOsHelperBundle.ensure_helper_installed so that the
    # standard validation + concurrent-install safeguards are honoured.
    #
    # @raise [RuntimeError] if installation fails validation
    def install_helper = MacOsHelperBundle.ensure_helper_installed(out_stream: @out_stream)

    # Force-replace the installed bundle regardless of current validity, then
    # re-validate.  Use this for the --repair path where the user knows the
    # existing install is stale or macOS TCC has lost track of it.
    #
    # @return [String] installed bundle path on success
    # @raise  [RuntimeError] if reinstallation fails validation
    def reinstall_helper
      MacOsHelperBundle.install_helper_bundle(out_stream: @out_stream)

      unless MacOsHelperBundle.helper_installed_and_valid?
        raise 'Helper reinstallation failed validation. ' \
          'Try running wifi-wand-macos-setup again.'
      end

      MacOsHelperBundle.installed_bundle_path
    end

    # Open the macOS System Settings pane for Location Services so the user
    # can grant permission to wifiwand-helper.
    def open_location_settings
      system('open', 'x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices')
    end

    private def check_authorization(helper_path, valid)
      return [false, 'Helper not installed or not valid'] unless valid

      helper_result = MacOsHelperBundle.run_bounded_helper_command(helper_path, 'check-permission')
      return [false, 'Permission status unknown'] unless helper_result

      unless helper_result[:status].success? && !helper_result[:stdout].strip.empty?
        return [false, 'Could not check permission status']
      end

      result = JSON.parse(helper_result[:stdout])
      [result['authorized'] == true, result['message'] || 'Unknown']
    rescue JSON::ParserError
      [false, 'Could not parse permission status response']
    rescue Errno::ENOENT
      [false, 'Helper executable not found']
    end
  end
end
