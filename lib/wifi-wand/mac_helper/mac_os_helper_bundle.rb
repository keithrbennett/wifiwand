# frozen_string_literal: true

# Manages the lifecycle of the macOS Wi-Fi helper app that runs privileged Swift code.
# The module installs, compiles, and signs the helper bundle per WifiWand version so
# network queries can bypass TCC redactions on Sonoma+ while remaining opt-in via env flag.
# Entry points:
#   * WifiWand::MacOsHelperBundle.ensure_helper_installed -> installs/validates the helper bundle.
#   * MacOsHelperClient#connected_network_name -> runs the helper's `current-network` command.
#   * MacOsHelperClient#scan_networks -> runs the helper's `scan-networks` command.
#   * MacOsHelperClient#available? -> tells callers when the helper can safely be invoked.

require 'rubygems/version'
require_relative 'mac_os_helper_artifacts'

module WifiWand
  module MacOsHelperBundle
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')
    # Only enable the helper on macOS Sonoma (14.0) and newer where redactions occur
    MINIMUM_HELPER_VERSION = Gem::Version.new('14.0')
    # Allows power users/CI to opt out of helper usage via environment flag
    DISABLE_ENV_KEY = 'WIFIWAND_DISABLE_MAC_HELPER'
    HELPER_COMMAND_TIMEOUT_SECONDS =
      (ENV['WIFIWAND_HELPER_TIMEOUT_SECONDS'] || 3.0).to_f
    HELPER_TERMINATION_WAIT_SECONDS = 0.25
    MANIFEST_FILENAME = 'INSTALL_MANIFEST.json'

    module_function def versioned_install_dir = File.join(INSTALL_PARENT, helper_version)

    module_function def installed_bundle_path = File.join(versioned_install_dir, BUNDLE_NAME)

    module_function def installed_executable_path = File.join(installed_bundle_path, 'Contents', 'MacOS',
      EXECUTABLE_NAME)

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

require_relative 'mac_os_helper_installer'
require_relative 'mac_os_helper_client'

module WifiWand
  module MacOsHelperBundle
    module_function def helper_installed_and_valid? = MacOsHelperInstaller.helper_installed_and_valid?

    module_function def ensure_helper_installed(out_stream: $stdout)
      MacOsHelperInstaller.ensure_helper_installed(out_stream: out_stream)
    end

    module_function def install_helper_bundle(out_stream: $stdout)
      MacOsHelperInstaller.install_helper_bundle(out_stream: out_stream)
    end

    module_function def install_lock_path = MacOsHelperInstaller.install_lock_path

    module_function def install_manifest_path = MacOsHelperInstaller.install_manifest_path

    module_function def helper_bundle_valid?(bundle_path)
      MacOsHelperInstaller.helper_bundle_valid?(bundle_path)
    end

    module_function def helper_help_output?(command_output)
      MacOsHelperInstaller.helper_help_output?(command_output)
    end

    module_function def installed_bundle_current? = MacOsHelperInstaller.installed_bundle_current?

    module_function def run_bounded_helper_command(executable_path, command, on_timeout: nil)
      MacOsHelperInstaller.run_bounded_helper_command(executable_path, command, on_timeout: on_timeout)
    end

    module_function def terminate_helper_process(wait_thr)
      MacOsHelperInstaller.terminate_helper_process(wait_thr)
    end

    module_function def helper_exited_within_grace_period?(wait_thr)
      MacOsHelperInstaller.helper_exited_within_grace_period?(wait_thr)
    end

    module_function def with_install_lock(&) = MacOsHelperInstaller.with_install_lock(&)

    module_function def stage_helper_bundle(staged_bundle_path)
      MacOsHelperInstaller.stage_helper_bundle(staged_bundle_path)
    end

    module_function def publish_staged_bundle(staged_bundle_path)
      MacOsHelperInstaller.publish_staged_bundle(staged_bundle_path)
    end

    module_function def publish_release_symlink(release_bundle_path, publish_token)
      MacOsHelperInstaller.publish_release_symlink(release_bundle_path, publish_token)
    end

    module_function def migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
      MacOsHelperInstaller.migrate_legacy_bundle_to_release(release_bundle_path, publish_token)
    end

    module_function def bundle_release_path(publish_token)
      MacOsHelperInstaller.bundle_release_path(publish_token)
    end

    module_function def staged_bundle_symlink_path(publish_token)
      MacOsHelperInstaller.staged_bundle_symlink_path(publish_token)
    end

    module_function def legacy_executable_symlink_path(publish_token)
      MacOsHelperInstaller.legacy_executable_symlink_path(publish_token)
    end

    module_function def legacy_info_plist_path = MacOsHelperInstaller.legacy_info_plist_path

    module_function def legacy_code_resources_path = MacOsHelperInstaller.legacy_code_resources_path

    module_function def resolved_installed_bundle_target
      MacOsHelperInstaller.resolved_installed_bundle_target
    end

    module_function def cleanup_previous_release(previous_release_path)
      MacOsHelperInstaller.cleanup_previous_release(previous_release_path)
    end

    module_function def sync_legacy_bundle_metadata(release_bundle_path, publish_token)
      MacOsHelperInstaller.sync_legacy_bundle_metadata(release_bundle_path, publish_token)
    end

    module_function def backup_legacy_bundle_metadata(publish_token)
      MacOsHelperInstaller.backup_legacy_bundle_metadata(publish_token)
    end

    module_function def backup_legacy_metadata_file(path, publish_token)
      MacOsHelperInstaller.backup_legacy_metadata_file(path, publish_token)
    end

    module_function def restore_legacy_bundle_metadata(backup_paths, publish_token)
      MacOsHelperInstaller.restore_legacy_bundle_metadata(backup_paths, publish_token)
    end

    module_function def restore_legacy_metadata_file(backup_path, target_path, publish_token)
      MacOsHelperInstaller.restore_legacy_metadata_file(backup_path, target_path, publish_token)
    end

    module_function def cleanup_legacy_bundle_metadata_backups(backup_paths)
      MacOsHelperInstaller.cleanup_legacy_bundle_metadata_backups(backup_paths)
    end

    module_function def switch_legacy_bundle_executable(release_bundle_path, publish_token)
      MacOsHelperInstaller.switch_legacy_bundle_executable(release_bundle_path, publish_token)
    end

    module_function def resolved_legacy_release_target = MacOsHelperInstaller.resolved_legacy_release_target

    module_function def unique_publish_token = MacOsHelperInstaller.unique_publish_token

    module_function def write_manifest = MacOsHelperInstaller.write_manifest

    module_function def read_install_manifest = MacOsHelperInstaller.read_install_manifest
  end

  MacOsWifiAuthHelper = MacOsHelperBundle unless const_defined?(:MacOsWifiAuthHelper, false)
end
