# frozen_string_literal: true

require 'json'
require_relative 'captive_portal_checker'

module WifiWand
  # Encapsulates the argument-parsing and probe-execution logic for the captive
  # portal helper script.  Keeping this logic in a module that can be +require+d
  # directly allows the spec suite (and SimpleCov) to exercise the code without
  # spawning a subprocess, while the thin CLI entry-point at the bottom of this
  # file preserves the existing runtime contract.
  module CaptivePortalProbeHelper
    # Parses command-line arguments into an endpoint hash.
    #
    # @param argv [Array<String>] positional args: url, expected_code, optional expected_body
    # @return [Hash] with :url (String), :expected_code (Integer), :expected_body (String|nil)
    # @raise [ArgumentError] when url or expected_code are absent or expected_code is non-numeric
    def self.parse_argv(argv)
      url, expected_code_arg, expected_body = argv

      url_missing = url.nil? || url.strip.empty?
      raise ArgumentError, 'url argument is required' if url_missing

      expected_code_arg_missing = expected_code_arg.nil? || expected_code_arg.strip.empty?
      raise ArgumentError, 'expected_code argument is required' if expected_code_arg_missing

      {
        url:           url,
        expected_code: Integer(expected_code_arg),
        expected_body: expected_body.to_s.strip.empty? ? nil : expected_body,
      }
    end

    # Parses +argv+, performs a captive portal probe, and writes a JSON result
    # hash to +output+.  Any +ArgumentError+ raised during argument parsing is
    # caught and serialised as an indeterminate result so the parent process
    # always receives valid JSON.
    #
    # @param argv    [Array<String>]           see {parse_argv}
    # @param output  [IO]                      destination for the JSON result (default: $stdout)
    # @param checker [CaptivePortalChecker, nil]  optional pre-built checker; a fresh one is
    #                                          created when nil (useful for injecting test doubles)
    def self.run(argv, output: $stdout, checker: nil)
      endpoint = parse_argv(argv)
      checker ||= CaptivePortalChecker.new(verbose: false, output: $stderr)
      result = checker.send(:perform_captive_portal_check, endpoint)
      output.print(JSON.generate(result))
      output.flush
    rescue ArgumentError => e
      output.print(JSON.generate(
        { state: 'indeterminate', error_class: e.class.to_s, error_message: e.message }))
      output.flush
    end
  end
end

# Entry point: only execute when this file is run directly as a script.
# The guard keeps the file safely require-able by the spec suite.
WifiWand::CaptivePortalProbeHelper.run(ARGV) if $PROGRAM_NAME == __FILE__
