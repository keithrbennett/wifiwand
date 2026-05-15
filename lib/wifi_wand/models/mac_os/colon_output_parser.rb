# frozen_string_literal: true

module WifiWand
  module MacOsColonOutputParser
    private def colon_output_to_hash(output)
      output.each_line.with_object({}) do |line, hash|
        key, value = line.split(':', 2)
        next unless key && !value.nil?

        hash[key.strip] = value.to_s.strip
      end
    end
  end
end
