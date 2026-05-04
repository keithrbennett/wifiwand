# frozen_string_literal: true

require_relative '../services/command_executor'

module WifiWand
  # Runs the direct Swift-source runtime path used for macOS connect/disconnect
  # operations. Read/query operations that need a stable app identity flow
  # through MacOsHelperClient and the compiled helper app instead.
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
        result = run_command_using_args(['swift', '-e', 'import CoreWLAN'], raise_on_error: false)
        log_swift_probe_failure(result) if !result.success? && verbose?
        result.success?
      rescue WifiWand::CommandNotFoundError
        log_swift_command_not_found if verbose?
        false
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

    private def log_swift_probe_failure(failure)
      case failure.exitstatus
      when 127
        log_swift_command_not_found(exitstatus: failure.exitstatus)
      when 1
        out_stream.puts "CoreWLAN framework not available (exit code #{failure.exitstatus}). Install Xcode."
      else
        out_stream.puts "Swift/CoreWLAN check failed with exit code #{failure.exitstatus}: " \
          "#{swift_probe_failure_text(failure)}"
      end
    end

    private def log_swift_command_not_found(exitstatus: nil)
      exit_code_text = exitstatus ? " (exit code #{exitstatus})" : ''
      out_stream.puts "Swift command not found#{exit_code_text}. Install Xcode Command Line Tools."
    end

    private def swift_probe_failure_text(failure)
      if failure.respond_to?(:text)
        failure.text.to_s.strip
      else
        failure.combined_output.to_s.strip
      end
    end
  end
end
