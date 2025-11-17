# frozen_string_literal: true

# QR Code Generator (unit)
# Verifies command construction without invoking external tools:
# - Stdout mode ('-') uses `-t ANSI` and returns '-'
# - Output format flags for .svg/.eps
# Overwrite flows are covered separately in qr_overwrite_spec.rb

require_relative '../../../spec_helper'
require 'fileutils'

describe 'QR Code Generator (unit)' do
  let(:model) { create_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }

  before(:each) do
    model.verbose_mode = false
    allow(model).to receive(:command_available?).with('qrencode').and_return(true)
    allow(model).to receive(:connected_network_name).and_return(ssid)
    allow(model).to receive(:connection_security_type).and_return(security)
    allow(model).to receive(:connected_network_password).and_return(password)
    allow(model).to receive(:network_hidden?).and_return(false)
  end

  after(:each) do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
  end

  it "prints ANSI QR to stdout when filespec is '-' and returns '-'" do
    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(['qrencode', '-t', 'ANSI'])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect {
 result = model.generate_qr_code('-') }.to output(a_string_including('[QR-ANSI]')).to_stdout
    expect(result).to eq('-')
  end

  it 'returns ANSI QR string without printing when delivery_mode is :return' do
    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(['qrencode', '-t', 'ANSI'])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect { result = model.generate_qr_code('-', delivery_mode: :return) }.not_to output.to_stdout
    expect(result).to eq("[QR-ANSI]\n")
  end

  it 'raises WifiWand::Error when ANSI generation command fails' do
    expect(model).to receive(:run_os_command)
      .and_raise(WifiWand::CommandExecutor::OsCommandError.new(1, 'qrencode', 'boom'))

    expect {
      silence_output { model.generate_qr_code('-', delivery_mode: :print) }
    }.to raise_error(WifiWand::Error, /Failed to generate QR code/)
  end

  it 'uses provided password without querying system password' do
    provided_password = 'provided123'

    # Ensure generator does not try to fetch stored password when one is given
    expect(model).not_to receive(:connected_network_password)

    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd).to include('-o')
      expect(cmd).to include('TestNetwork-qr-code.png')
      expect(cmd.last).to include('P:provided123')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  [
    { filespec: 'out.svg', type: 'SVG' },
    { filespec: 'out.eps', type: 'EPS' }
  ].each do |tc|
    it "uses -t #{tc[:type]} flag when filespec ends with #{File.extname(tc[:filespec])}" do
      expect(model).to receive(:run_os_command) do |cmd|
        expect(cmd).to be_an(Array)
        expect(cmd).to include('qrencode')
        expect(cmd).to include('-t')
        expect(cmd).to include(tc[:type])
        expect(cmd).to include('-o')
        expect(cmd).to include(tc[:filespec])
        command_result(stdout: '')
      end

      result = silence_output { model.generate_qr_code(tc[:filespec]) }
      expect(result).to eq(tc[:filespec])
    end
  end

      it 'generates QR code with H:false for visible (broadcast) networks' do
    allow(model).to receive(:network_hidden?).and_return(false)

    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:false')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates QR code with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:true')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates ANSI QR with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_os_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(['qrencode', '-t', 'ANSI'])
      expect(cmd.last).to include('H:true')
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect {
 result = model.generate_qr_code('-') }.to output(a_string_including('[QR-ANSI]')).to_stdout
    expect(result).to eq('-')
  end

  # Overwrite behavior is covered in qr_overwrite_spec.rb
end
