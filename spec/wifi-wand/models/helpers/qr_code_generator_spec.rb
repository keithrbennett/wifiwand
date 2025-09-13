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
    allow(model).to receive(:command_available_using_which?).with('qrencode').and_return(true)
    allow(model).to receive(:connected_network_name).and_return(ssid)
    allow(model).to receive(:connection_security_type).and_return(security)
    allow(model).to receive(:connected_network_password).and_return(password)
  end

  after(:each) do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
  end

  it "prints ANSI QR to stdout when filespec is '-' and returns '-'" do
    expect(model).to receive(:run_os_command) do |cmd, *_|
      expect(cmd).to start_with('qrencode -t ANSI ')
      "[QR-ANSI]\n"
    end

    result = nil
    expect { result = model.generate_qr_code('-') }.to output(a_string_including('[QR-ANSI]')).to_stdout
    expect(result).to eq('-')
  end

  it "returns ANSI QR string without printing when delivery_mode is :return" do
    expect(model).to receive(:run_os_command) do |cmd, *_|
      expect(cmd).to start_with('qrencode -t ANSI ')
      "[QR-ANSI]\n"
    end

    result = nil
    expect { result = model.generate_qr_code('-', delivery_mode: :return) }.not_to output.to_stdout
    expect(result).to eq("[QR-ANSI]\n")
  end

  it "uses provided password without querying system password" do
    provided_password = 'provided123'

    # Ensure generator does not try to fetch stored password when one is given
    expect(model).not_to receive(:connected_network_password)

    expect(model).to receive(:run_os_command) do |cmd, *_|
      expect(cmd).to include('qrencode ')
      expect(cmd).to include(" -o TestNetwork-qr-code.png ")
      expect(cmd).to include('P:provided123')
      ''
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  [
    { filespec: 'out.svg', flag: '-t SVG' },
    { filespec: 'out.eps', flag: '-t EPS' }
  ].each do |tc|
    it "uses #{tc[:flag]} flag when filespec ends with #{File.extname(tc[:filespec])}" do
      expect(model).to receive(:run_os_command) do |cmd, *_|
        expect(cmd).to include(" #{tc[:flag]} ")
        expect(cmd).to include(" -o #{tc[:filespec]} ")
        ''
      end

      result = nil
      silence_output { result = model.generate_qr_code(tc[:filespec]) }
      expect(result).to eq(tc[:filespec])
    end
  end

  # Overwrite behavior is covered in qr_overwrite_spec.rb
end
