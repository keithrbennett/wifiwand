# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'json'
require 'rbconfig'
require 'shellwords'
require_relative 'mac_os_wifi_auth_helper'

module WifiWand
  module MacHelperRelease
    PENDING_NOTARIZATION_STATUS = 'In Progress'
    SIGNING_INSTRUCTIONS_PATH = 'dev/docs/MACOS_CODE_SIGNING_INSTRUCTIONS.md'
    DEFAULT_NOTARYTOOL_PROFILE = 'wifiwand-notarytool'

    # Public signing credentials (visible in all signed binaries - no need to hide)
    APPLE_TEAM_ID = ENV.fetch('WIFIWAND_APPLE_TEAM_ID', '97P9SZU9GG')
    CODESIGN_IDENTITY = ENV.fetch('WIFIWAND_CODESIGN_IDENTITY',
      'Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)')

    # Message templates for output
    module Messages
      SECTION_SEPARATOR = '=' * 60
      SUBSECTION_SEPARATOR = '-' * 60

      def self.building_helper(source:, destination:, identity:)
        <<~MSG
          Building helper for distribution...
            Source: #{source}
            Destination: #{destination}
            Identity: #{identity}

        MSG
      end

      HELPER_BUILT_SUCCESS = <<~MSG

        ✓ Helper built and signed successfully!

        Next steps:
          1. Test the signed helper: bin/mac-helper test
          2. Notarize for distribution: bin/mac-helper notarize
      MSG

      TESTING_HEADER = <<~MSG
        Testing signed helper...

        Code signature:
      MSG

      SIGNATURE_VALID = '✓ Signature is valid'

      def self.signature_invalid(stderr)
        <<~MSG
          ✗ Signature verification failed:
          #{stderr}
        MSG
      end

      def self.helper_executed_success(stdout)
        <<~MSG
          ✓ Helper executed successfully
          Output:
          #{stdout}
        MSG
      end

      def self.helper_execution_failed(stderr)
        <<~MSG
          ✗ Helper execution failed:
          #{stderr}
        MSG
      end

      SOURCE_ATTESTATION_VALID = '✓ Source attestation matches committed Swift source and bundle'

      def self.notarizing_header(bundle_path:, profile_name:, keychain_path:)
        details = [
          "  Bundle: #{bundle_path}",
          "  Keychain Profile: #{profile_name}",
        ]
        details << "  Keychain: #{keychain_path}" if keychain_path && !keychain_path.empty?

        <<~MSG
          Notarizing helper for distribution...
          #{details.join("\n")}

          Creating zip archive...
        MSG
      end

      def self.zip_created(zip_path)
        <<~MSG
          ✓ Created #{zip_path}

          Submitting to Apple for notarization...
          (This usually takes 2-5 minutes)

        MSG
      end

      NOTARIZATION_SUCCESS = <<~MSG
        ✓ Notarization successful!

        Stapling notarization ticket...
      MSG

      TICKET_STAPLED = '✓ Notarization ticket stapled'

      def self.staple_warning(stderr)
        <<~MSG
          Warning: Could not staple ticket (this is optional):
          #{stderr}
        MSG
      end

      def self.helper_ready(bundle_path)
        <<~MSG

          ✓ Helper is now signed and notarized!

          Next steps:
            1. Test the notarized helper: bin/mac-helper test
            2. Commit the signed helper: git add #{bundle_path}
            3. Build and release the gem: gem build wifi-wand.gemspec
        MSG
      end

      def self.workflow_starting
        <<~MSG
          Starting complete helper release workflow...
          #{SECTION_SEPARATOR}

        MSG
      end

      WORKFLOW_SEPARATOR = <<~MSG.freeze

        #{SECTION_SEPARATOR}

      MSG

      WORKFLOW_COMPLETE = <<~MSG
        ✓ Complete release workflow finished!

        The helper is now ready for gem distribution.
        Don't forget to commit the signed binary:
          git add libexec/macos/wifiwand-helper.app
          git commit -m 'Update signed and notarized macOS helper'
      MSG

      def self.codesign_status_header
        <<~MSG
          Code Signing Status
          #{SECTION_SEPARATOR}

          Signature Details:
          #{SUBSECTION_SEPARATOR}
        MSG
      end

      SIGNATURE_VERIFICATION_HEADER = <<~MSG.freeze

        Signature Verification:
        #{SUBSECTION_SEPARATOR}
      MSG

      NOTARIZATION_STATUS_HEADER = <<~MSG.freeze

        Notarization Status:
        #{SUBSECTION_SEPARATOR}
      MSG

      def self.bundle_not_found(bundle_path)
        <<~MSG
          Helper bundle not found at #{bundle_path}
          Run: bin/mac-helper build
        MSG
      end

      def self.signature_invalid_status(stderr)
        <<~MSG
          ✗ Signature is invalid:
          #{stderr}
        MSG
      end

      def self.source_attestation_invalid(error_message)
        <<~MSG
          ✗ Source attestation failed:
          #{error_message}
        MSG
      end
    end

    # Helper methods for operations
    module Operations
      def self.require_macos!(task_name)
        abort "#{task_name} is only supported on macOS hosts." unless RbConfig::CONFIG['host_os'] =~ /darwin/i
      end

      def self.helper_executable_path
        helper = WifiWand::MacOsWifiAuthHelper
        File.join(helper.source_bundle_path, 'Contents', 'MacOS', WifiWand::MacOsWifiAuthHelper::EXECUTABLE_NAME)
      end

      def self.get_binary_architectures(binary_path)
        stdout, _stderr, status = Open3.capture3('lipo', '-archs', binary_path)
        return [] unless status.success?

        stdout.strip.split
      end

      def self.verify_universal_binary(binary_path)
        archs = get_binary_architectures(binary_path)
        has_arm64 = archs.include?('arm64')
        has_x86_64 = archs.include?('x86_64')

        unless has_arm64 && has_x86_64
          missing = []
          missing << 'arm64' unless has_arm64
          missing << 'x86_64' unless has_x86_64
          puts "⚠ Warning: Binary is missing architectures: #{missing.join(', ')}"
          puts "  Found: #{archs.join(', ')}"
          puts "  This binary will not work on #{missing.include?('arm64') ? 'Apple Silicon' : 'Intel'} Macs."
          return false
        end

        puts '✓ Universal binary confirmed (arm64 + x86_64)'
        true
      end

      def self.verify_identity_configured(identity)
        return unless identity.include?('YOUR_TEAM_ID_HERE') || identity.include?('Your Name')

        abort <<~ERROR
          Error: CODESIGN_IDENTITY is not configured.

          Please update the values in lib/wifi-wand/mac_helper/mac_helper_release.rb:
            APPLE_TEAM_ID = 'TEAM123'
            CODESIGN_IDENTITY = 'Developer ID Application: Your Name (TEAM123)'

          To find your Developer ID certificate:
            security find-identity -v -p codesigning

          See #{SIGNING_INSTRUCTIONS_PATH} for detailed instructions.
        ERROR
      end

      def self.verify_identity_exists(identity)
        stdout, _stderr, status = Open3.capture3('security', 'find-identity', '-v', '-p', 'codesigning')
        return if status.success? && stdout.include?(identity)

        abort <<~ERROR.chomp
          Error: Could not find code signing identity '#{identity}'

          Run: security find-identity -v -p codesigning
        ERROR
      end

      def self.verify_signature(bundle_path)
        puts 'Verifying signature...'
        _stdout, stderr, status = Open3.capture3('codesign', '--verify', '--verbose', bundle_path)
        message = status.success? ? Messages::SIGNATURE_VALID : Messages.signature_invalid(stderr)
        puts message
        exit 1 unless status.success?
      end

      def self.test_helper_execution(executable)
        puts 'Testing helper execution...'
        stdout, stderr, status = Open3.capture3(executable, 'current-network')
        message = if status.success?
          Messages.helper_executed_success(stdout)
        else
          Messages.helper_execution_failed(stderr)
        end
        puts message
        exit 1 unless status.success?
      end

      def self.verify_team_id_configured(team_id)
        abort <<~ERROR if team_id == 'YOUR_TEAM_ID_HERE'
          Error: APPLE_TEAM_ID is not configured.

          Please update the value in lib/wifi-wand/mac_helper/mac_helper_release.rb:
            APPLE_TEAM_ID = 'TEAM123'

          See #{SIGNING_INSTRUCTIONS_PATH} for detailed instructions.
        ERROR
      end

      def self.notarytool_store_credentials_command(profile_name, team_id:, apple_id: 'you@example.com')
        escaped_profile = Shellwords.escape(profile_name)
        escaped_apple_id = Shellwords.escape(apple_id)
        escaped_team_id = Shellwords.escape(team_id)

        "xcrun notarytool store-credentials #{escaped_profile} " \
          "--apple-id #{escaped_apple_id} --team-id #{escaped_team_id}"
      end

      def self.verify_credentials(profile_name, team_id, command_hint: 'bin/mac-helper notarize')
        return if profile_name && !profile_name.empty?

        abort <<~ERROR
          Error: notarytool keychain profile is not configured.

          Runtime notarization commands now require a notarytool keychain profile instead of
          passing the app-specific password on the command line.

          Create the default profile once:
            #{notarytool_store_credentials_command(DEFAULT_NOTARYTOOL_PROFILE, team_id: team_id)}

          Then run:
            #{command_hint}

          Optional environment variables:
            WIFIWAND_NOTARYTOOL_PROFILE  - Profile name to use at runtime
            WIFIWAND_NOTARYTOOL_KEYCHAIN - Custom keychain path if not using the login keychain

          notarytool prompts for the app-specific password during store-credentials, which keeps it
          out of process argv and shell history.

          See #{SIGNING_INSTRUCTIONS_PATH} for detailed instructions.
        ERROR
      end

      def self.create_zip(bundle_path, zip_path)
        FileUtils.rm_f(zip_path)
        _stdout, stderr, status = Open3.capture3('ditto', '-c', '-k', '--keepParent', bundle_path, zip_path)
        abort "Failed to create zip: #{stderr}" unless status.success?
      end

      def self.submit_for_notarization(zip_path, profile_name, keychain_path, team_id)
        run_notarytool(
          ['submit', zip_path, '--wait'],
          profile_name:    profile_name,
          keychain_path:   keychain_path,
          team_id:         team_id,
          failure_message: 'Notarization failed. Check the output above for details.'
        )
      end

      def self.staple_ticket(bundle_path)
        _stdout, stderr, status = Open3.capture3('xcrun', 'stapler', 'staple', bundle_path)
        message = status.success? ? Messages::TICKET_STAPLED : Messages.staple_warning(stderr)
        puts message
      end

      def self.run_notarytool(args, profile_name:, keychain_path:, team_id:,
        failure_message:, suppress_output: false)
        command = %w[xcrun notarytool] + args + ['--keychain-profile', profile_name]
        command += ['--keychain', keychain_path] if keychain_path && !keychain_path.empty?
        stdout, stderr, status = Open3.capture3(*command)
        puts stdout unless stdout.empty? || suppress_output
        puts stderr unless stderr.empty? || suppress_output
        unless status.success?
          if stderr.match?(/store-credentials|keychain profile|No Keychain password item/i)
            setup_command = notarytool_store_credentials_command(profile_name, team_id: team_id)
            abort <<~ERROR
              #{failure_message}

              notarytool could not load the keychain profile "#{profile_name}".

              Create or refresh it with:
                #{setup_command}

              notarytool will prompt for the app-specific password instead of exposing it in argv.
            ERROR
          end

          abort(failure_message)
        end
        stdout
      end
    end

    # Public API - main operations
    module_function def verify_source_attestation!
      WifiWand::MacOsWifiAuthHelper.verify_source_bundle_current!
      puts Messages::SOURCE_ATTESTATION_VALID
    rescue => e
      abort Messages.source_attestation_invalid(e.message)
    end

    module_function def build_signed_helper
      Operations.require_macos!(__method__.to_s)
      identity = CODESIGN_IDENTITY
      Operations.verify_identity_configured(identity)
      Operations.verify_identity_exists(identity)
      ENV['WIFIWAND_CODESIGN_IDENTITY'] ||= identity

      helper = WifiWand::MacOsWifiAuthHelper
      source = helper.source_swift_path
      destination = File.join(helper.source_bundle_path, 'Contents', 'MacOS', WifiWand::MacOsWifiAuthHelper::EXECUTABLE_NAME)

      puts Messages.building_helper(source: source, destination: destination, identity: identity)
      helper.compile_helper(source, destination, out_stream: $stdout)
      helper.write_source_bundle_manifest

      puts "\nVerifying binary architectures..."
      Operations.verify_universal_binary(destination)
      verify_source_attestation!

      puts Messages::HELPER_BUILT_SUCCESS
    end

    module_function def test_signed_helper
      Operations.require_macos!(__method__.to_s)
      helper = WifiWand::MacOsWifiAuthHelper
      executable = Operations.helper_executable_path
      abort "Helper not found at #{executable}. Run: bin/mac-helper build" unless File.exist?(executable)

      verify_source_attestation!

      puts Messages::TESTING_HEADER
      system('codesign', '-dvv', helper.source_bundle_path)
      puts

      puts 'Binary architectures:'
      archs = Operations.get_binary_architectures(executable)
      puts "  #{archs.join(', ')}"
      puts

      Operations.verify_signature(helper.source_bundle_path)
      puts
      Operations.test_helper_execution(executable)
    end

    module_function def notarize_helper
      Operations.require_macos!(__method__.to_s)
      creds = fetch_notary_credentials!(command_hint: 'bin/mac-helper notarize')
      profile_name = creds[:profile_name]
      keychain_path = creds[:keychain_path]
      team_id = creds[:team_id]

      helper = WifiWand::MacOsWifiAuthHelper
      bundle_path = helper.source_bundle_path
      zip_path = "#{bundle_path}.zip"
      abort "Helper bundle not found at #{bundle_path}. Run: bin/mac-helper build" \
        unless File.exist?(bundle_path)

      verify_source_attestation!

      stdout, stderr, status = Open3.capture3('codesign', '-dv', bundle_path)
      codesign_output = [stdout, stderr].join("\n")
      if !status.success?
        abort <<~ERROR.chomp
          Error: Could not inspect code signature.

          #{codesign_output.strip}

          Run: bin/mac-helper build
        ERROR
      elsif codesign_output.match?(/\badhoc\b/i)
        abort <<~ERROR.chomp
          Error: Helper is ad-hoc signed. Must be signed with Developer ID.
          Rebuild it with your configured Developer ID identity:
          Run: bin/mac-helper build
        ERROR
      end

      puts Messages.notarizing_header(
        bundle_path:   bundle_path,
        profile_name:  profile_name,
        keychain_path: keychain_path
      )
      Operations.create_zip(bundle_path, zip_path)
      puts Messages.zip_created(zip_path)

      stdout = Operations.submit_for_notarization(zip_path, profile_name, keychain_path, team_id)
      unless stdout.include?('status: Accepted')
        abort 'Notarization was rejected. Check the output above for details.'
      end

      puts Messages::NOTARIZATION_SUCCESS
      Operations.staple_ticket(bundle_path)
      FileUtils.rm_f(zip_path)
      puts Messages.helper_ready(bundle_path)
    end

    module_function def notarization_history
      creds = fetch_notary_credentials!(command_hint: 'bin/mac-helper history')
      puts 'Recent notarization submissions:'
      Operations.run_notarytool(
        ['history'],
        **creds,
        failure_message: 'Unable to fetch notarization history.'
      )
    end

    module_function def notarization_status(submission_id)
      if submission_id.nil? || submission_id.empty?
        abort 'Error: Submission ID is required. Use --submission-id <uuid> ' \
          'or let the script auto-select.'
      end
      creds = fetch_notary_credentials!(command_hint: 'bin/mac-helper info --submission-id <uuid>')
      puts "Status for submission #{submission_id}:"
      Operations.run_notarytool(
        ['info', submission_id],
        **creds,
        failure_message: 'Unable to fetch notarization status. Check the submission ID and try again.'
      )
    end

    module_function def notarization_log(submission_id)
      if submission_id.nil? || submission_id.empty?
        abort 'Error: Submission ID is required. Use --submission-id <uuid> ' \
          'or let the script auto-select.'
      end
      creds = fetch_notary_credentials!(command_hint: 'bin/mac-helper log --submission-id <uuid>')
      puts "Log for submission #{submission_id}:"
      Operations.run_notarytool(
        ['log', submission_id],
        **creds,
        failure_message: 'Unable to fetch notarization log. Check the submission ID and try again.'
      )
    end

    module_function def cancel_notarization(submission_id)
      if submission_id.nil? || submission_id.empty?
        abort 'Error: Submission ID is required. Use --submission-id <uuid> ' \
          'or let the script auto-select.'
      end
      creds = fetch_notary_credentials!(command_hint: 'bin/mac-helper cancel --submission-id <uuid>')
      validate_pending_submission_for_cancel!(submission_id, creds: creds)
      puts "Canceling submission #{submission_id}..."
      Operations.run_notarytool(
        ['queue', 'remove', submission_id],
        **creds,
        failure_message: 'Unable to cancel notarization request.'
      )
      puts "✓ Submission #{submission_id} removed from notary queue."
    end

    module_function def latest_submission_id = select_submission_id(order: :desc)
    module_function def oldest_submission_id = select_submission_id(order: :asc)

    module_function def select_submission_id(order:, pending_only: false)
      normalized_order = normalize_submission_order(order)
      entries = notarization_history_entries(command_hint: 'bin/mac-helper history')
      return nil if entries.nil? || entries.empty?

      ordered_entries = case normalized_order
                        when :asc
                          entries.reverse
                        else
                          entries
      end

      if pending_only
        ordered_entries = ordered_entries.select { |item| pending_submission?(item) }
      end

      entry = ordered_entries.first
      entry && entry['id']
    end

    module_function def notarization_history_entries(command_hint:)
      creds = fetch_notary_credentials!(command_hint: command_hint)
      notarization_history_entries_with_credentials(creds)
    end

    module_function def notarization_history_entries_with_credentials(creds)
      response = Operations.run_notarytool(
        ['history', '--output-format', 'json'],
        **creds,
        failure_message: 'Unable to fetch notarization history.',
        suppress_output: true
      )
      data = JSON.parse(response)
      data['history'] || []
    rescue JSON::ParserError => e
      warn "Warning: unable to parse notarytool history JSON (#{e.message})."
      nil
    end

    module_function def pending_submission?(entry)
      entry && entry['status'] == PENDING_NOTARIZATION_STATUS
    end

    module_function def validate_pending_submission_for_cancel!(submission_id, creds:)
      entries = notarization_history_entries_with_credentials(creds)
      unless entries
        abort 'Error: Unable to validate notarization status from history. Run: bin/mac-helper history'
      end

      entry = entries.find { |item| item['id'] == submission_id }
      unless entry
        abort "Error: Submission #{submission_id} was not found in notarization history. " \
          'Run: bin/mac-helper history'
      end

      return if pending_submission?(entry)

      status = entry['status'] || 'Unknown'
      abort "Error: Submission #{submission_id} is #{status} and cannot be canceled. " \
        'Only pending submissions can be canceled.'
    end

    module_function def normalize_submission_order(order = :desc)
      case order
      when :asc, :ascending
        :asc
      when :desc, :descending
        :desc
      else
        raise ArgumentError, "Invalid order: #{order.inspect}. Use :asc/:ascending or :desc/:descending"
      end
    end

    module_function def release_helper
      puts Messages.workflow_starting
      build_signed_helper
      puts Messages::WORKFLOW_SEPARATOR
      test_signed_helper
      puts Messages::WORKFLOW_SEPARATOR
      notarize_helper
      puts Messages::WORKFLOW_SEPARATOR, Messages::WORKFLOW_COMPLETE
    end

    module_function def codesign_status
      Operations.require_macos!(__method__.to_s)
      helper = WifiWand::MacOsWifiAuthHelper
      bundle_path = helper.source_bundle_path
      executable_path = Operations.helper_executable_path
      unless File.exist?(bundle_path)
        puts Messages.bundle_not_found(bundle_path)
        exit 1
      end

      verify_source_attestation!

      puts Messages.codesign_status_header
      system('codesign', '-dvv', bundle_path)

      puts "\nBinary Architectures:"
      puts Messages::SUBSECTION_SEPARATOR
      archs = Operations.get_binary_architectures(executable_path)
      if archs.include?('arm64') && archs.include?('x86_64')
        puts "✓ Universal binary (#{archs.join(', ')})"
      else
        puts "⚠ Not universal: #{archs.join(', ')}"
      end

      puts Messages::SIGNATURE_VERIFICATION_HEADER
      _stdout, stderr, status = Open3.capture3('codesign', '--verify', '--verbose', bundle_path)
      message = status.success? ? Messages::SIGNATURE_VALID : Messages.signature_invalid_status(stderr)
      puts message

      puts Messages::NOTARIZATION_STATUS_HEADER
      stdout, _stderr, status = Open3.capture3('spctl', '-a', '-vv', '-t', 'install', bundle_path)
      puts stdout
      message = if status.success?
        '✓ Helper is notarized and will run without Gatekeeper warnings'
      elsif stdout.include?('source=Notarized Developer ID')
        '✓ Helper is notarized'
      else
        "⚠ Helper is not notarized - users may see Gatekeeper warnings\n  Run: bin/mac-helper notarize"
      end
      puts message
    end

    module_function def fetch_notary_credentials!(command_hint:)
      profile_name = ENV.fetch('WIFIWAND_NOTARYTOOL_PROFILE', DEFAULT_NOTARYTOOL_PROFILE).to_s.strip
      keychain_path = ENV['WIFIWAND_NOTARYTOOL_KEYCHAIN']&.strip
      team_id = APPLE_TEAM_ID
      Operations.verify_team_id_configured(team_id)
      Operations.verify_credentials(profile_name, team_id, command_hint: command_hint)
      { profile_name: profile_name, keychain_path: keychain_path, team_id: team_id }
    end
  end
end
