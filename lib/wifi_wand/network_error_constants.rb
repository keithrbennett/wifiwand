# frozen_string_literal: true

require 'socket'
require 'timeout'

require_relative 'errors'
require_relative 'services/command_executor'

module WifiWand
  module NetworkErrorConstants
    EXPECTED_NETWORK_ERRORS = [
      SocketError,
      IOError,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      Timeout::Error,
    ].freeze

    NETWORK_OPERATION_COMMAND_ERRORS = [
      WifiWand::CommandExecutor::OsCommandError,
      WifiWand::CommandTimeoutError,
      WifiWand::CommandNotFoundError,
      WifiWand::CommandSpawnError,
    ].freeze
  end
end
