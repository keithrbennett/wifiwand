# The functionality of this software is very difficult to test,
# sinece it relies on external conditions that cannot be faked.
# These tests merely run the commands and assert that no
# error has occurred; they don't make any attempt to verify the data.
# Many of them are run once with the wifi on, and once when it's off.


load File.join(File.dirname(__FILE__), 'mac-wifi')

module MacWifi

describe Model do


  subject { Model.new }

  context 'turning wifi on and off' do
    it 'can turn wifi on' do
      subject.wifi_off
      expect(subject.wifi_on?).to eq(false)
      subject.wifi_on
      expect(subject.wifi_on?).to eq(true)
    end

    it 'can turn wifi off' do
      subject.wifi_on
      expect(subject.wifi_on?).to eq(true)
      subject.wifi_off
      expect(subject.wifi_on?).to eq(false)
    end

    it 'can cycle network' do
      subject.wifi_on
      subject.cycle_network
      expect(subject.wifi_on?).to eq(true)
    end
  end

  shared_examples_for 'testing to see commands complete without error' do |wifi_starts_on|

    it 'can determine if connected to Internet' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      # We cannot assert that we're connected to the Internet even
      # if the wifi is on, because we're probably not connected to a network.
      subject.connected_to_internet?
    end

    it 'can get wifi port' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.wifi_hardware_port
    end

    it 'can list info' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.wifi_info
    end

    it 'can list available networks' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.available_network_info
    end

    it 'can list preferred networks' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.preferred_networks
    end

    it 'can see if wifi is on' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.wifi_on?
    end

    it 'can query the connected network name' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      name = subject.connected_network_name
      unless subject.wifi_on?
        expect(name).to eq(nil)
      end
    end

    # it 'can attempt to connect to a network' do
    # pending 'cannot reliably expect any given network to be available'
    # end

    # it 'can determine the IP address on the network' do
    #   pending 'How to reliably reproduce connection to a network?'
    # end

    it 'can determine the current network' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      network = subject.current_network
      unless subject.wifi_on?
        expect(network).to eq(nil)
      end
    end

    it 'can call disconnect twice consecutively' do
      wifi_starts_on ? subject.wifi_on : subject.wifi_off
      subject.disconnect
      subject.disconnect
    end
  end

  context 'wifi starts on' do # without a context block the way that rspec expands the examples causes the parameters to overwrite each other
    include_examples 'testing to see commands complete without error', true
  end

  context 'wifi starts off' do # without a context block the way that rspec expands the examples causes the parameters to overwrite each other
    include_examples 'testing to see commands complete without error', false
  end
end

end
