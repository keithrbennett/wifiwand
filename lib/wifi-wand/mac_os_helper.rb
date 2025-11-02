# frozen_string_literal: true

require 'fileutils'
require 'open3'

module WifiWand
  module MacOsHelper
    BUNDLE_NAME = 'wifiwand-helper.app'
    EXECUTABLE_NAME = 'wifiwand-helper'
    INSTALL_PARENT = File.join(Dir.home, 'Library', 'Application Support', 'WifiWand')

    module_function

    def ensure_helper_installed!(out_stream: $stdout)
      return installed_bundle_path if helper_ready?

      out_stream.puts 'Installing wifiwand macOS helper...' if out_stream
      install_helper_bundle(out_stream: out_stream)
      installed_bundle_path
    end

    def helper_ready?
      executable = installed_executable_path
      File.exist?(executable) && File.executable?(executable)
    end

    def installed_bundle_path
      File.join(versioned_install_dir, BUNDLE_NAME)
    end

    def installed_executable_path
      File.join(installed_bundle_path, 'Contents', 'MacOS', EXECUTABLE_NAME)
    end

    def versioned_install_dir
      File.join(INSTALL_PARENT, helper_version)
    end

    def helper_version
      WifiWand::VERSION
    end

    def install_helper_bundle(out_stream: $stdout)
      FileUtils.mkdir_p(versioned_install_dir)
      FileUtils.rm_rf(installed_bundle_path)
      FileUtils.cp_r(source_bundle_path, installed_bundle_path)
      compile_helper(source_swift_path, installed_executable_path, out_stream: out_stream)
      write_manifest
    end

    def compile_helper(source, destination, out_stream: $stdout)
      FileUtils.mkdir_p(File.dirname(destination))
      command = [
        'swiftc',
        source,
        '-framework', 'Cocoa',
        '-framework', 'CoreLocation',
        '-framework', 'CoreWLAN',
        '-o', destination
      ]
      stdout, stderr, status = Open3.capture3(*command)
      unless status.success?
        raise "Failed to compile WiFi helper (status=#{status.exitstatus}): #{stderr.empty? ? stdout : stderr}"
      end
      FileUtils.chmod(0o755, destination)
      out_stream.puts 'Helper compiled successfully.' if out_stream
    end

    def source_bundle_path
      File.expand_path('../../libexec/macos/wifiwand-helper.app', __dir__)
    end

    def source_swift_path
      File.expand_path('../../libexec/macos/src/wifiwand-helper.swift', __dir__)
    end

    def write_manifest
      FileUtils.mkdir_p(versioned_install_dir)
      File.write(File.join(versioned_install_dir, 'VERSION'), helper_version)
    end

    def helper_info
      {
        version: helper_version,
        installed_bundle: installed_bundle_path,
        installed_executable: installed_executable_path,
        source_bundle: source_bundle_path,
        source_swift: source_swift_path
      }
    end
  end
end
