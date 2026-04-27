# frozen_string_literal: true

module NetworkStateManager
  class Session
    attr_reader :model, :network_state

    def initialize(model:)
      @model = model
      @network_state = nil
    end

    def capture_state
      @network_state = model.capture_network_state
    end

    def restore_state(fail_silently: true)
      return unless @network_state

      model.restore_network_state(@network_state, fail_silently: fail_silently)
    end

    def state_available?
      !@network_state.nil?
    end
  end

  def self.model
    session.model
  end

  def self.start_session(model: build_model)
    @session = Session.new(model: model)
  end

  def self.clear_session
    @session = nil
  end

  def self.session
    @session ||= Session.new(model: build_model)
  end

  def self.build_model
    options = { verbose: ENV['WIFIWAND_VERBOSE'] == 'true' }
    WifiWand::OperatingSystems.create_model_for_current_os(options)
  end

  def self.capture_state
    session.capture_state
  end

  def self.restore_state(fail_silently: true)
    session.restore_state(fail_silently: fail_silently)
  end

  def self.state_available?
    session.state_available?
  end

  def self.network_state
    session.network_state
  end
end
