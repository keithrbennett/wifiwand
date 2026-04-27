# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require_relative 'mac_os_helper_artifacts'

module WifiWand
  module MacOsWifiAuthHelper
    SOURCE_MANIFEST_FILENAME = 'wifiwand-helper.source-manifest.json'

    # Returns the path to the Swift source file in the gem's libexec directory
    #
    # @return [String] absolute path to wifiwand-helper.swift source file
    #   Example: /path/to/gem/libexec/macos/src/wifiwand-helper.swift
    module_function def source_swift_path = File.expand_path(
      '../../../libexec/macos/src/wifiwand-helper.swift', __dir__)

    # Returns the path to the source attestation manifest committed with the helper bundle.
    #
    # @return [String] absolute path to the helper source manifest
    module_function def source_bundle_manifest_path =
      File.expand_path("../../../libexec/macos/#{SOURCE_MANIFEST_FILENAME}", __dir__)

    module_function def source_swift_fingerprint = Digest::SHA256.file(source_swift_path).hexdigest

    module_function def source_bundle_current?
      manifest = read_source_bundle_manifest

      if manifest
        manifest['helper_version'] == helper_version &&
          manifest['source_sha256'] == source_swift_fingerprint &&
          manifest['bundle_fingerprint'] == bundle_fingerprint(source_bundle_path)
      else
        false
      end
    end

    module_function def verify_source_bundle_current!
      source_bundle_current? || raise(source_bundle_mismatch_message)
    end

    module_function def compile_helper(source, destination, out_stream: $stdout)
      FileUtils.mkdir_p(File.dirname(destination))

      # Build universal binary (ARM64 + x86_64) for compatibility with all Macs
      arm64_binary = "#{destination}.arm64"
      x86_64_binary = "#{destination}.x86_64"

      begin
        compile_architecture(source, arm64_binary, 'arm64-apple-macos11', 'ARM64')
        compile_architecture(source, x86_64_binary, 'x86_64-apple-macos11', 'x86_64')
        create_universal_binary(destination, arm64_binary, x86_64_binary)
      ensure
        FileUtils.rm_f([arm64_binary, x86_64_binary])
      end

      FileUtils.chmod(0o755, destination)
      out_stream&.puts 'Helper compiled successfully.'

      # Code sign the helper bundle to enable proper TCC registration
      sign_helper_bundle(destination, out_stream: out_stream)
    end

    module_function def compile_architecture(source, output, target, arch_name)
      command = [
        'swiftc', source,
        '-target', target,
        '-framework', 'Cocoa',
        '-framework', 'CoreLocation',
        '-framework', 'CoreWLAN',
        '-o', output
      ]
      stdout, stderr, status = Open3.capture3(*command)
      return if status.success?

      error_output = stderr.empty? ? stdout : stderr
      raise "Failed to compile #{arch_name} binary (status=#{status.exitstatus}): #{error_output}"
    end

    module_function def create_universal_binary(destination, *architecture_binaries)
      stdout, stderr, status = Open3.capture3('lipo', '-create', '-output', destination,
        *architecture_binaries)
      return if status.success?

      error_output = stderr.empty? ? stdout : stderr
      raise "Failed to create universal binary (status=#{status.exitstatus}): #{error_output}"
    end

    module_function def sign_helper_bundle(executable_path, out_stream: $stdout)
      # Get the bundle path from the executable path
      bundle_path = executable_path.split('/Contents/MacOS/').first

      # Use environment variable or default to Keith's Developer ID
      identity = ENV['WIFIWAND_CODESIGN_IDENTITY'] ||
        'Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)'

      # Path to entitlements file
      entitlements_path = File.expand_path('../../../libexec/macos/wifiwand-helper.entitlements', __dir__)

      command = [
        'codesign',
        '--force',
        '--sign', identity,
        '--deep',
        '--options', 'runtime',
        '--entitlements', entitlements_path,
        '--timestamp',
        bundle_path
      ]

      out_stream&.puts "Signing helper bundle with Developer ID '#{identity}'..."
      stdout, stderr, status = Open3.capture3(*command)

      unless status.success?
        raise "Failed to code sign helper bundle (status=#{status.exitstatus}): " \
          "#{stderr.empty? ? stdout : stderr}"
      end

      out_stream&.puts 'Helper bundle signed successfully.'
    end

    module_function def write_source_bundle_manifest
      File.write(source_bundle_manifest_path, JSON.pretty_generate(source_bundle_manifest_payload))
    end

    module_function def source_bundle_manifest_payload
      {
        'helper_version'     => helper_version,
        'source_path'        => relative_helper_path(source_swift_path),
        'source_sha256'      => source_swift_fingerprint,
        'bundle_path'        => relative_helper_path(source_bundle_path),
        'bundle_fingerprint' => bundle_fingerprint(source_bundle_path),
      }
    end

    module_function def read_source_bundle_manifest
      if File.exist?(source_bundle_manifest_path)
        JSON.parse(File.read(source_bundle_manifest_path))
      end
    rescue JSON::ParserError
      nil
    end

    module_function def source_bundle_mismatch_message
      "Shipped macOS helper bundle is out of sync with #{relative_helper_path(source_swift_path)}. " \
        'Run `bundle exec rake swift:compile` or `bin/mac-helper build` to rebuild the signed bundle ' \
        "and refresh #{relative_helper_path(source_bundle_manifest_path)}."
    end
  end
end
