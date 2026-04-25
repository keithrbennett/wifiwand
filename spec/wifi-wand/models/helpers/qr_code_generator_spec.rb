# frozen_string_literal: true

# QR Code Generator (unit)
# Verifies command construction without invoking external tools:
# - Stdout mode ('-') uses `-t ANSI` and returns '-'
# - File mode stages output in a sibling temp file before rename
# - Output format flags for .svg/.eps
# Overwrite flows are covered separately in qr_overwrite_spec.rb

require_relative '../../../spec_helper'
require 'fileutils'

describe 'QR Code Generator (unit)' do
  let(:model) { create_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }

  before do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
    model.verbose_mode = false
    allow(model).to receive(:command_available?).with('qrencode').and_return(true)
    allow(model).to receive_messages(
      connected_network_name:     ssid,
      connection_security_type:   security,
      connected_network_password: password,
      network_hidden?:            false
    )
  end

  after do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
  end

  def staged_output_for(cmd)
    cmd[cmd.index('-o') + 1]
  end

  it "prints ANSI QR to stdout when filespec is '-' and returns '-'" do
    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect { result = model.generate_qr_code('-') }.to output(a_string_including('[QR-ANSI]')).to_stdout
    expect(result).to eq('-')
  end

  it 'returns ANSI QR string without printing when delivery_mode is :return' do
    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect { result = model.generate_qr_code('-', delivery_mode: :return) }.not_to output.to_stdout
    expect(result).to eq("[QR-ANSI]\n")
  end

  it 'raises WifiWand::Error when ANSI generation command fails' do
    expect(model).to receive(:run_command_using_args)
      .and_raise(os_command_error(exitstatus: 1, command: 'qrencode', text: 'boom'))

    expect do
      silence_output { model.generate_qr_code('-', delivery_mode: :print) }
    end.to raise_error(WifiWand::Error, /Failed to generate QR code/)
  end

  it 'uses provided password without querying system password' do
    provided_password = 'provided123'

    expect(model).not_to receive(:connected_network_password)

    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd).to include('-o')
      expect(staged_output_for(cmd)).to match(%r{\./TestNetwork-qr-code-.*\.png\z})
      expect(cmd.last).to include('P:provided123')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  it 'surfaces exact-identity errors when the current SSID is redacted' do
    allow(model).to receive(:connected_network_name).and_raise(
      WifiWand::MacOsRedactionError.new(operation_description: 'current WiFi network queries')
    )

    expect do
      silence_output { model.generate_qr_code }
    end.to raise_error(WifiWand::MacOsRedactionError, /Exact WiFi network identity.*wifi-wand-macos-setup/)
  end

  [
    { filespec: 'out.svg', type: 'SVG' },
    { filespec: 'out.eps', type: 'EPS' },
  ].each do |tc|
    it "uses -t #{tc[:type]} flag when filespec ends with #{File.extname(tc[:filespec])}" do
      expect(model).to receive(:run_command_using_args) do |cmd|
        expect(cmd).to be_an(Array)
        expect(cmd).to include('qrencode')
        expect(cmd).to include('-t')
        expect(cmd).to include(tc[:type])
        expect(cmd).to include('-o')
        expect(staged_output_for(cmd)).to match(%r{\./out-.*#{Regexp.escape(File.extname(tc[:filespec]))}\z})
        command_result(stdout: '')
      end

      result = silence_output { model.generate_qr_code(tc[:filespec]) }
      expect(result).to eq(tc[:filespec])
    end
  end

  it 'generates QR code with H:false for visible (broadcast) networks' do
    allow(model).to receive(:network_hidden?).and_return(false)

    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:false')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates QR code with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:true')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates ANSI QR with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command_using_args) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      expect(cmd.last).to include('H:true')
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = nil
    expect { result = model.generate_qr_code('-') }.to output(a_string_including('[QR-ANSI]')).to_stdout
    expect(result).to eq('-')
  end

  # Overwrite behavior is covered in qr_overwrite_spec.rb
end
