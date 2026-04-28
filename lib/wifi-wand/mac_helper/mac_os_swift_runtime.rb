# frozen_string_literal: true

require_relative '../services/command_executor'

module WifiWand
  class MacOsSwiftRuntime
    SWIFT_CONNECT_FALLBACK_PATTERNS = [
      /code:\s*-3900/i,
      /code:\s*-3905/i,
      /corewlan generic error/i,
      /possible keychain access or authentication issue/i,
      /network not found/i,
      /tmpErr\s*\(code:\s*82\)/i,
      /couldn(?:\?\?\?|')t be completed.*tmpErr/i,
    ].freeze

    def initialize(command_runner:, out_stream_proc:, verbose_proc:)
      @command_runner = command_runner
      @out_stream_proc = out_stream_proc
      @verbose_proc = verbose_proc
    end

    def swift_and_corewlan_present?
      return @swift_and_corewlan_present if defined?(@swift_and_corewlan_present)

      @swift_and_corewlan_present = begin
        run_command_using_args(['swift', '-e', 'import CoreWLAN'], false)
        true
      rescue WifiWand::CommandExecutor::OsCommandError => e
        log_swift_probe_failure(e) if verbose?
        false
      rescue => e
        out_stream.puts "Unexpected error checking Swift/CoreWLAN: #{e.message}" if verbose?
        false
      end
    end

    def run_swift_command(basename, *args)
      run_command_using_args(['swift', swift_filespec_for(basename)] + args)
    end

    def connect(network_name, password = nil)
      args = [network_name]
      args << password if password
      run_swift_command('WifiNetworkConnector', *args)
    end

    def disconnect
      run_swift_command('WifiNetworkDisconnector')
    end

    def fallback_connect_error?(error_text)
      SWIFT_CONNECT_FALLBACK_PATTERNS.any? { |pattern| pattern.match?(error_text.to_s) }
    end

    private def run_command_using_args(*, **)
      @command_runner.call(*, **)
    end

    private def out_stream = @out_stream_proc.call

    private def verbose? = @verbose_proc.call

    private def swift_filespec_for(basename)
      File.absolute_path(File.join(__dir__, 'swift', "#{basename}.swift"))
    end

    private def log_swift_probe_failure(error)
      case error.exitstatus
      when 127
        out_stream.puts "Swift command not found (exit code #{error.exitstatus}). " \
          'Install Xcode Command Line Tools.'
      when 1
        out_stream.puts "CoreWLAN framework not available (exit code #{error.exitstatus}). Install Xcode."
      else
        out_stream.puts "Swift/CoreWLAN check failed with exit code #{error.exitstatus}: " \
          "#{error.text.to_s.strip}"
      end
    end
  end
end
