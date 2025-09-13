# frozen_string_literal: true

module NetworkStateManager

  def self.model
    options = OpenStruct.new(verbose: ENV['WIFIWAND_VERBOSE'] == 'true')
    @model ||= WifiWand::OperatingSystems.create_model_for_current_os(options)
  end

  def self.capture_state
    begin
      @network_state = model.capture_network_state
      if @network_state[:network_name]
        puts <<~MESSAGE

          Captured network state for restoration: #{@network_state[:network_name]}

        MESSAGE
      end
    rescue => e
      puts <<~MESSAGE

        Warning: Could not capture network state: #{e.message}
        Network restoration will not be available for this test run.

      MESSAGE
      @network_state = nil
    end
  end

  def self.restore_state
    return unless @network_state
    
    model.restore_network_state(@network_state, fail_silently: true)
  end

  def self.state_available?
    !@network_state.nil?
  end

  def self.network_state
    @network_state
  end
end
