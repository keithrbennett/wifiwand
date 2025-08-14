module NetworkStateManager

  def self.model
    @model ||= WifiWand::OperatingSystems.create_model_for_current_os(OpenStruct.new(verbose: false))
  end

  def self.capture_state
    begin
      @network_state = model.capture_network_state
      if @network_state[:network_name]
        puts "\nCaptured network state for restoration: #{@network_state[:network_name]}"
        puts "Note: On macOS, you may be prompted for keychain access permissions."
      end
    rescue => e
      puts "\nWarning: Could not capture network state: #{e.message}"
      puts "Network restoration will not be available for this test run."
      @network_state = nil
    end
  end

  def self.restore_state
    return unless @network_state
    
    begin
      model.restore_network_state(@network_state)
    rescue => e
      puts "Warning: Could not restore network state: #{e.message}"
    end
  end

  def self.state_available?
    !@network_state.nil?
  end

  def self.network_state
    @network_state
  end
end