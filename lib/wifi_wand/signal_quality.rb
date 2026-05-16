# frozen_string_literal: true

module WifiWand
  SignalQuality = Struct.new(:value, :unit, keyword_init: true) do
    def to_s
      unit == :dbm ? "#{value} #{unit_label}" : "#{value}#{unit_label}"
    end

    def unit_label
      unit == :dbm ? 'dBm' : '%'
    end
  end
end
