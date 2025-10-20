# frozen_string_literal: true

module CommandResultHelper
  def build_command_result(stdout: '', stderr: '', exitstatus: 0, command: nil, duration: 0.0)
    WifiWand::CommandExecutor::OsCommandResult.new(
      stdout: stdout,
      stderr: stderr,
      combined_output: [stdout, stderr].join,
      exitstatus: exitstatus,
      command: command,
      duration: duration
    )
  end

  alias command_result build_command_result
end

RSpec.configure do |config|
  config.include CommandResultHelper
end
