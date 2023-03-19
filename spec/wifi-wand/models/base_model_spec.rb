require_relative '../../../lib/wifi-wand/models/mac_os_model'

module WifiWand

  describe BaseModel::OsCommandError do
    subject { BaseModel::OsCommandError.new(1, 'the command', 'failed to produce an x') }

    specify 'to_h produces a correct hash' do
      expect(subject.to_h).to eq(exitstatus: 1, command: 'the command', text: 'failed to produce an x')
    end

    specify 'raising the error produces the correct string' do
      expect(subject.to_s).to eq(
        "WifiWand::BaseModel::OsCommandError: Error code 1, command = the command, text = failed to produce an x"
      )
    end
  end
end
