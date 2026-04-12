# frozen_string_literal: true

require 'json'
require_relative 'captive_portal_checker'

url, expected_code_arg = ARGV
endpoint = {
  url:           url,
  expected_code: Integer(expected_code_arg),
}

checker = WifiWand::CaptivePortalChecker.new(verbose: false, output: $stderr)
result = checker.send(:perform_captive_portal_check, endpoint)

print(JSON.generate(result))
$stdout.flush
