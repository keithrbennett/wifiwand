# frozen_string_literal: true

require_relative '../spec_helper'
require 'fileutils'

describe 'QR Code Overwrite Confirmation', :os_ubuntu do
  let(:model) { create_ubuntu_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }
  let(:filename) { 'TestNetwork-qr-code.png' }

  before(:each) do
    # Stub environment and dependencies
    allow(model).to receive(:command_available_using_which?).with('qrencode').and_return(true)
    allow(model).to receive(:connected_network_name).and_return(ssid)
    allow(model).to receive(:connection_security_type).and_return(security)
    allow(model).to receive(:connected_network_password).and_return(password)
  end

  after(:each) do
    FileUtils.rm_f(filename)
  end

  it 'prompts and proceeds when user confirms overwrite' do
    # Create an existing file to trigger overwrite flow
    File.write(filename, 'old')

    # Simulate interactive TTY and user confirmation
    allow($stdin).to receive(:tty?).and_return(true)
    allow($stdin).to receive(:gets).and_return("y\n")

    # Ensure qrencode is invoked (but do not actually run it)
    expect(model).to receive(:run_os_command) do |cmd, *_rest|
      expect(cmd).to start_with("qrencode -o #{filename} ")
      ''
    end

    result = nil
    silence_output do
      result = model.generate_qr_code
    end
    expect(result).to eq(filename)
  end

  it 'prompts and aborts when user declines overwrite' do
    File.write(filename, 'old')

    allow($stdin).to receive(:tty?).and_return(true)
    allow($stdin).to receive(:gets).and_return("n\n")

    expect(model).not_to receive(:run_os_command)

    expect {
      silence_output { model.generate_qr_code }
    }.to raise_error(WifiWand::Error, /cancelled: file exists/i)
  end

  it 'errors in non-interactive mode when file exists' do
    File.write(filename, 'old')

    allow($stdin).to receive(:tty?).and_return(false)

    expect(model).not_to receive(:run_os_command)

    expect {
      silence_output { model.generate_qr_code }
    }.to raise_error(WifiWand::Error, /already exists.*Delete the file first/i)
  end
end
