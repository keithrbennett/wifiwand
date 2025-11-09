# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require_relative 'mac_os_wifi_auth_helper'

module WifiWand
  module MacHelperRelease
    # Public signing credentials (visible in all signed binaries - no need to hide)
    APPLE_TEAM_ID = ENV.fetch('WIFIWAND_APPLE_TEAM_ID', '97P9SZU9GG')
    CODESIGN_IDENTITY = ENV.fetch('WIFIWAND_CODESIGN_IDENTITY',
      'Developer ID Application: Bennett Business Solutions, Inc. (97P9SZU9GG)')

    # Message templates for output
    module Messages
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
          1. Test the signed helper: bundle exec rake dev:test_signed_helper
          2. Notarize for distribution: bundle exec rake dev:notarize_helper
      MSG

      TESTING_HEADER = <<~MSG
        Testing signed helper...

        Code signature:
      MSG

      SIGNATURE_VALID = "✓ Signature is valid"

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

      def self.notarizing_header(bundle_path:, apple_id:, team_id:)
        <<~MSG
          Notarizing helper for distribution...
            Bundle: #{bundle_path}
            Apple ID: #{apple_id}
            Team ID: #{team_id}

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

      TICKET_STAPLED = "✓ Notarization ticket stapled"

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
            1. Test the notarized helper: bundle exec rake dev:test_signed_helper
            2. Commit the signed helper: git add #{bundle_path}
            3. Build and release the gem: gem build wifi-wand.gemspec
        MSG
      end

      def self.workflow_starting
        <<~MSG
          Starting complete helper release workflow...
          #{"=" * 60}

        MSG
      end

      WORKFLOW_SEPARATOR = <<~MSG

        #{"=" * 60}

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
          #{"=" * 60}

          Signature Details:
          #{"-" * 60}
        MSG
      end

      SIGNATURE_VERIFICATION_HEADER = <<~MSG

        Signature Verification:
        #{"-" * 60}
      MSG

      NOTARIZATION_STATUS_HEADER = <<~MSG

        Notarization Status:
        #{"-" * 60}
      MSG

      def self.bundle_not_found(bundle_path)
        <<~MSG
          Helper bundle not found at #{bundle_path}
          Run: bundle exec rake swift:compile_helper
        MSG
      end

      def self.signature_invalid_status(stderr)
        <<~MSG
          ✗ Signature is invalid:
          #{stderr}
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

      def self.verify_identity_configured(identity)
        return unless identity.include?('YOUR_TEAM_ID_HERE') || identity.include?('Your Name')

        abort <<~ERROR
          Error: CODESIGN_IDENTITY is not configured.

          Please update the values in lib/wifi-wand/mac_helper_release.rb:
            APPLE_TEAM_ID = 'TEAM123'
            CODESIGN_IDENTITY = 'Developer ID Application: Your Name (TEAM123)'

          To find your Developer ID certificate:
            security find-identity -v -p codesigning

          See docs/dev/MACOS_CODE_SIGNING.md for detailed instructions.
        ERROR
      end

      def self.verify_identity_exists(identity)
        stdout, _stderr, status = Open3.capture3('security', 'find-identity', '-v', '-p', 'codesigning')
        return if status.success? && stdout.include?(identity)

        abort "Error: Could not find code signing identity '#{identity}'\n\nRun: security find-identity -v -p codesigning"
      end

      def self.verify_signature(bundle_path)
        puts "Verifying signature..."
        _stdout, stderr, status = Open3.capture3('codesign', '--verify', '--verbose', bundle_path)
        message = status.success? ? Messages::SIGNATURE_VALID : Messages.signature_invalid(stderr)
        puts message
        exit 1 unless status.success?
      end

      def self.test_helper_execution(executable)
        puts "Testing helper execution..."
        stdout, stderr, status = Open3.capture3(executable, '--command', 'current-network')
        message = status.success? ? Messages.helper_executed_success(stdout) : Messages.helper_execution_failed(stderr)
        puts message
        exit 1 unless status.success?
      end

      def self.verify_team_id_configured(team_id)
        abort <<~ERROR if team_id == 'YOUR_TEAM_ID_HERE'
          Error: APPLE_TEAM_ID is not configured.

          Please update the value in lib/wifi-wand/mac_helper_release.rb:
            APPLE_TEAM_ID = 'TEAM123'

          See docs/dev/MACOS_CODE_SIGNING.md for detailed instructions.
        ERROR
      end

      def self.verify_credentials(apple_id, apple_password, command_hint: 'bundle exec rake dev:notarize_helper')
        return if apple_id && apple_password

        missing = []
        missing << 'WIFIWAND_APPLE_DEV_ID' unless apple_id
        missing << 'WIFIWAND_APPLE_DEV_PASSWORD' unless apple_password
        missing_list = missing.empty? ? 'required credentials' : missing.join(', ')

        abort <<~ERROR
          Error: Apple credentials not set (missing #{missing_list}).

          Required environment variables (private credentials only):
            WIFIWAND_APPLE_DEV_ID       - Your Apple ID email (e.g., you@example.com)
            WIFIWAND_APPLE_DEV_PASSWORD - App-specific password from appleid.apple.com

          Usage (direct environment variables):
            WIFIWAND_APPLE_DEV_ID="you@example.com" \\
            WIFIWAND_APPLE_DEV_PASSWORD="xxxx-xxxx-xxxx-xxxx" \\
              #{command_hint}

          Usage (with 1Password CLI references from .env.release):
            op run --env-file=.env.release -- #{command_hint}

          You can substitute your own secret-management workflow if preferred; the rake task only needs
          the two environment variables set before it runs.

          Note: Team ID and codesign identity are hardcoded in lib/wifi-wand/mac_helper_release.rb
          (they're public values visible in signed binaries anyway).

          See docs/dev/MACOS_CODE_SIGNING.md for detailed instructions.
        ERROR
      end

      def self.create_zip(bundle_path, zip_path)
        FileUtils.rm_f(zip_path)
        _stdout, stderr, status = Open3.capture3('ditto', '-c', '-k', '--keepParent', bundle_path, zip_path)
        abort "Failed to create zip: #{stderr}" unless status.success?
      end

      def self.submit_for_notarization(zip_path, apple_id, team_id, apple_password)
        run_notarytool(
          ['submit', zip_path, '--wait'],
          apple_id: apple_id,
          apple_password: apple_password,
          team_id: team_id,
          failure_message: 'Notarization failed. Check the output above for details.'
        )
      end

      def self.staple_ticket(bundle_path)
        _stdout, stderr, status = Open3.capture3('xcrun', 'stapler', 'staple', bundle_path)
        message = status.success? ? Messages::TICKET_STAPLED : Messages.staple_warning(stderr)
        puts message
      end

      def self.run_notarytool(args, apple_id:, apple_password:, team_id:, failure_message:)
        command = ['xcrun', 'notarytool'] + args + [
          '--apple-id', apple_id,
          '--team-id', team_id,
          '--password', apple_password
        ]
        stdout, stderr, status = Open3.capture3(*command)
        puts stdout unless stdout.empty?
        puts stderr unless stderr.empty?
        abort(failure_message) unless status.success?
        stdout
      end
    end

    # Public API - main operations
    module_function

    def build_signed_helper
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
      puts Messages::HELPER_BUILT_SUCCESS
    end

    def test_signed_helper
      Operations.require_macos!(__method__.to_s)
      helper = WifiWand::MacOsWifiAuthHelper
      executable = Operations.helper_executable_path
      abort "Helper not found at #{executable}. Run: bundle exec rake dev:build_signed_helper" unless File.exist?(executable)

      puts Messages::TESTING_HEADER
      system('codesign', '-dvv', helper.source_bundle_path)
      puts
      Operations.verify_signature(helper.source_bundle_path)
      puts
      Operations.test_helper_execution(executable)
    end

    def notarize_helper
      Operations.require_macos!(__method__.to_s)
      creds = fetch_notary_credentials!(command_hint: 'bundle exec rake dev:notarize_helper')
      apple_id = creds[:apple_id]
      apple_password = creds[:apple_password]
      team_id = creds[:team_id]

      helper = WifiWand::MacOsWifiAuthHelper
      bundle_path = helper.source_bundle_path
      zip_path = "#{bundle_path}.zip"
      abort "Helper bundle not found at #{bundle_path}. Run: bundle exec rake dev:build_signed_helper" unless File.exist?(bundle_path)

      stdout, _stderr, status = Open3.capture3('codesign', '-dv', bundle_path)
      abort "Error: Helper is ad-hoc signed. Must be signed with Developer ID.\nRun: bundle exec rake dev:build_signed_helper" if status.success? && stdout.include?('adhoc')

      puts Messages.notarizing_header(bundle_path: bundle_path, apple_id: apple_id, team_id: team_id)
      Operations.create_zip(bundle_path, zip_path)
      puts Messages.zip_created(zip_path)

      stdout = Operations.submit_for_notarization(zip_path, apple_id, team_id, apple_password)
      abort "Notarization was rejected. Check the output above for details." unless stdout.include?('status: Accepted')

      puts Messages::NOTARIZATION_SUCCESS
      Operations.staple_ticket(bundle_path)
      FileUtils.rm_f(zip_path)
      puts Messages.helper_ready(bundle_path)
    end

    def notarization_history
      creds = fetch_notary_credentials!(command_hint: 'bundle exec rake dev:notarization_history')
      puts 'Recent notarization submissions:'
      Operations.run_notarytool(
        ['history'],
        **creds,
        failure_message: 'Unable to fetch notarization history.'
      )
    end

    def notarization_status(submission_id)
      abort 'Error: SUBMISSION_ID is required (pass SUBMISSION_ID=<uuid>).' unless submission_id && !submission_id.empty?
      creds = fetch_notary_credentials!(command_hint: 'bundle exec rake dev:notarization_status SUBMISSION_ID=<uuid>')
      puts "Status for submission #{submission_id}:"
      Operations.run_notarytool(
        ['status', submission_id],
        **creds,
        failure_message: 'Unable to fetch notarization status. Check the submission ID and try again.'
      )
    end

    def notarization_log(submission_id)
      abort 'Error: SUBMISSION_ID is required (pass SUBMISSION_ID=<uuid>).' unless submission_id && !submission_id.empty?
      creds = fetch_notary_credentials!(command_hint: 'bundle exec rake dev:notarization_log SUBMISSION_ID=<uuid>')
      puts "Log for submission #{submission_id}:"
      Operations.run_notarytool(
        ['log', submission_id],
        **creds,
        failure_message: 'Unable to fetch notarization log. Check the submission ID and try again.'
      )
    end

    def release_helper
      puts Messages.workflow_starting
      build_signed_helper
      puts Messages::WORKFLOW_SEPARATOR
      test_signed_helper
      puts Messages::WORKFLOW_SEPARATOR
      notarize_helper
      puts Messages::WORKFLOW_SEPARATOR, Messages::WORKFLOW_COMPLETE
    end

    def codesign_status
      Operations.require_macos!(__method__.to_s)
      helper = WifiWand::MacOsWifiAuthHelper
      bundle_path = helper.source_bundle_path
      unless File.exist?(bundle_path)
        puts Messages.bundle_not_found(bundle_path)
        exit 1
      end

      puts Messages.codesign_status_header
      system('codesign', '-dvv', bundle_path)

      puts Messages::SIGNATURE_VERIFICATION_HEADER
      _stdout, stderr, status = Open3.capture3('codesign', '--verify', '--verbose', bundle_path)
      message = status.success? ? Messages::SIGNATURE_VALID : Messages.signature_invalid_status(stderr)
      puts message

      puts Messages::NOTARIZATION_STATUS_HEADER
      stdout, _stderr, status = Open3.capture3('spctl', '-a', '-vv', '-t', 'install', bundle_path)
      puts stdout
      puts status.success? ? "✓ Helper is notarized and will run without Gatekeeper warnings" : stdout.include?('source=Notarized Developer ID') ? "✓ Helper is notarized" : "⚠ Helper is not notarized - users may see Gatekeeper warnings\n  Run: bundle exec rake dev:notarize_helper"
    end
    def fetch_notary_credentials!(command_hint:)
      apple_id = ENV['WIFIWAND_APPLE_DEV_ID']
      apple_password = ENV['WIFIWAND_APPLE_DEV_PASSWORD']
      team_id = APPLE_TEAM_ID
      Operations.verify_team_id_configured(team_id)
      Operations.verify_credentials(apple_id, apple_password, command_hint: command_hint)
      { apple_id: apple_id, apple_password: apple_password, team_id: team_id }
    end
  end
end
