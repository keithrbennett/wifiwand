# frozen_string_literal: true

module EnvBoolean
  TRUE_VALUES = %w[1 true yes on].freeze
  FALSE_VALUES = %w[0 false no off].freeze

  def self.enabled?(env, key, default:)
    parse(env[key], default: default)
  end

  def self.parse(value, default:)
    return default if value.nil?

    normalized_value = value.to_s.strip.downcase

    if TRUE_VALUES.include?(normalized_value)
      true
    elsif FALSE_VALUES.include?(normalized_value)
      false
    else
      default
    end
  end
  private_class_method :parse
end
