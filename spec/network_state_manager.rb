# frozen_string_literal: true

module NetworkStateManager
  def self.model
    options = OpenStruct.new(verbose: ENV['WIFIWAND_VERBOSE'] == 'true')
    @model ||= WifiWand::OperatingSystems.create_model_for_current_os(options)
  end

  def self.capture_state
    @network_state = model.capture_network_state
  end

  def self.restore_state(fail_silently: true)
    return unless @network_state

    model.restore_network_state(@network_state, fail_silently: fail_silently)
  end

  def self.state_available?
    !@network_state.nil?
  end

  def self.network_state
    @network_state
  end
end
