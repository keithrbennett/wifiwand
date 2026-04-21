# frozen_string_literal: true

require_relative 'spec_helper'

class DocsInfoCommandSpecModel < WifiWand::BaseModel
  def self.os_id = :doc_test

  def validate_os_preconditions = nil
  def probe_wifi_interface = 'wlan0'
  def connected? = true
  def connection_security_type = nil
  def default_interface = 'wlan0'
  def is_wifi_interface?(_iface) = true
  def mac_address = 'aa:bb:cc:dd:ee:ff'
  def nameservers = ['8.8.8.8', '8.8.4.4']
  def network_hidden? = false
  def open_resource(_resource) = nil
  def preferred_networks = %w[TestNetwork1 SavedNetwork1]
  def remove_preferred_network(_name) = nil
  # rubocop:disable Naming/AccessorMethodName
  def set_nameservers(_servers) = nil
  # rubocop:enable Naming/AccessorMethodName
  def wifi_off = nil
  def wifi_on = nil
  def wifi_on? = true
  def internet_tcp_connectivity? = true
  def dns_working? = true
  def captive_portal_state = :free
  def _available_network_names = %w[TestNetwork1 TestNetwork2]
  def _connected_network_name = 'TestNetwork1'
  def _connect(_network, _password) = nil
  def _disconnect = nil
  def _ip_address = '192.168.1.100'
  def _preferred_network_password(_network) = nil
end

RSpec.describe 'docs/INFO_COMMAND.md' do
  let(:documented_info_field_keys) do
    {
      'WiFi Status'                 => 'wifi_on',
      'Connected Network'           => 'network',
      'IP Address'                  => 'ip_address',
      'MAC Address'                 => 'mac_address',
      'TCP Working'                 => 'internet_tcp_connectivity',
      'DNS Working'                 => 'dns_working',
      'Captive Portal State'        => 'captive_portal_state',
      'Internet Connectivity State' => 'internet_connectivity_state',
      'Nameservers'                 => 'nameservers',
      'WiFi Interface'              => 'interface',
      'Default Route Interface'     => 'default_interface',
      'Timestamp'                   => 'timestamp',
    }
  end

  let(:info_command_doc) { File.read(File.expand_path('../docs/INFO_COMMAND.md', __dir__)) }
  let(:model) { DocsInfoCommandSpecModel.new(verbose: false, wifi_interface: 'wlan0') }
  let(:documented_section) do
    info_command_doc
      .split("## Information Provided\n\n", 2)
      .last
      &.split('## Comparing with Status Command', 2)
      &.first
  end

  it 'documents the same info payload keys returned by BaseModel#wifi_info' do
    expect(documented_section).not_to be_nil

    documented_labels = documented_section.scan(/^- \*\*(.+?)\*\*:/).flatten
    undocumented_labels = documented_labels - documented_info_field_keys.keys

    expect(undocumented_labels).to eq([])

    documented_keys = documented_labels.map { |label| documented_info_field_keys.fetch(label) }.sort
    expect(documented_keys).to eq(model.wifi_info.keys.sort)
  end
end
