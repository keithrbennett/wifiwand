# frozen_string_literal: true

RSpec::Matchers.define :be_nil_or_a_string do
  match { |actual| actual.nil? || actual.is_a?(String) }
  failure_message { |actual| "expected that #{actual.inspect} would be a String or nil" }
end

RSpec::Matchers.define :be_nil_or_a_string_matching do |regex|
  match { |actual| actual.nil? || (actual.is_a?(String) && actual.match?(regex)) }
  failure_message { |actual| "expected that #{actual.inspect} would be nil or a String matching #{regex.inspect}" }
end

RSpec::Matchers.define :be_nil_or_an_array_of_strings do
  match { |actual| actual.nil? || (actual.is_a?(Array) && actual.all? { |i| i.is_a?(String) }) }
  failure_message { |actual| "expected that #{actual.inspect} would be nil or an Array of Strings" }
end

RSpec::Matchers.define :be_nil_or_an_array_of_ip_addresses do
  match do |actual|
    return true if actual.nil?
    return false unless actual.is_a?(Array)
    actual.all? { |i| i.is_a?(String) && i.match?(/\A(\d{1,3}\.){3}\d{1,3}\z/) }
  end

  failure_message do |actual|
    "expected that #{actual.inspect} would be nil or an Array of IP address Strings"
  end
end