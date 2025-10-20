# frozen_string_literal: true

# QR Code Overwrite Confirmation (unit)
# Exercises all overwrite branches without calling external tools:
# - overwrite: true (success and deletion failure)
# - interactive TTY yes/no
# - non-interactive error guidance

require_relative '../../../spec_helper'
require 'fileutils'

describe 'QR Code Overwrite Confirmation' do
  let(:model) { create_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }
  let(:filename) { 'TestNetwork-qr-code.png' }

  before(:each) do
    # Stub environment and dependencies
    allow(model).to receive(:command_available?).with('qrencode').and_return(true)
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

    # Ensure we delete the file before invoking qrencode
    expect(File).to receive(:delete).with(filename).ordered.and_call_original
    # Ensure qrencode is invoked (but do not actually run it)
    expect(model).to receive(:run_os_command).with(a_string_starting_with("qrencode -o #{filename} ")).ordered.and_return(command_result(stdout: ''))

    result = silence_output { model.generate_qr_code }
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

  it 'deletes and proceeds when overwrite: true' do
    File.write(filename, 'old')

    expect(File).to receive(:delete).with(filename).ordered.and_call_original
    expect(model).to receive(:run_os_command).with(a_string_starting_with("qrencode -o #{filename} ")).ordered.and_return(command_result(stdout: ''))

    result = silence_output { model.generate_qr_code(nil, overwrite: true) }
    expect(result).to eq(filename)
    # We only assert command args and delete call in unit tests.
    # File recreation is the responsibility of qrencode (covered in integration tests).
    expect(File.exist?(filename)).to be false
  end

  it 'raises an error if deletion fails when overwrite: true' do
    File.write(filename, 'old')

    allow(File).to receive(:exist?).with(filename).and_return(true)
    allow(File).to receive(:delete).with(filename).and_raise(StandardError.new('cannot delete'))

    expect(model).not_to receive(:run_os_command)

    expect {
      silence_output { model.generate_qr_code(nil, overwrite: true) }
    }.to raise_error(WifiWand::Error, /could not be overwritten/)
  end

  it 'raises an error if deletion fails after interactive confirmation' do
    File.write(filename, 'old')

    allow($stdin).to receive(:tty?).and_return(true)
    allow($stdin).to receive(:gets).and_return("y\n")
    allow(File).to receive(:exist?).with(filename).and_return(true)
    allow(File).to receive(:delete).with(filename).and_raise(StandardError.new('cannot delete'))

    expect(model).not_to receive(:run_os_command)

    expect {
      silence_output { model.generate_qr_code }
    }.to raise_error(WifiWand::Error, /could not be overwritten/)
  end
end
