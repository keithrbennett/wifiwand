# frozen_string_literal: true

# QR Code Generator (unit)
# Verifies command construction without invoking external tools:
# - Stdout mode ('-') uses `-t ANSI` and returns '-'
# - File mode stages output in a sibling temp file before rename
# - Output format flags for .svg/.eps
# Overwrite flows are covered separately in qr_overwrite_spec.rb

require_relative '../../../spec_helper'
require 'fileutils'
require 'tmpdir'

describe 'QR Code Generator (unit)' do
  let(:model) { create_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }
  let(:out_stream) { StringIO.new }

  before do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
    model.verbose = false
    model.out_stream = out_stream
    allow(model).to receive(:command_available?).with('qrencode').and_return(true)
    allow(model).to receive_messages(
      connected_network_name:     ssid,
      connection_security_type:   security,
      preferred_network_password: password,
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

  def with_temp_dir
    temp_dir = Dir.mktmpdir('qr_code_generator_test')
    yield temp_dir
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  it "prints ANSI QR to stdout when filespec is '-' and returns '-'" do
    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = model.generate_qr_code('-')
    expect(out_stream.string).to include('[QR-ANSI]')
    expect(result).to eq('-')
  end

  it 'returns ANSI QR string without printing when delivery_mode is :return' do
    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = model.generate_qr_code('-', delivery_mode: :return)
    expect(out_stream.string).to eq('')
    expect(result).to eq("[QR-ANSI]\n")
  end

  it 'raises QrCodeGenerationError when ANSI generation command fails' do
    expect(model).to receive(:run_command)
      .and_raise(os_command_error(exitstatus: 1, command: 'qrencode', text: 'boom'))

    expect do
      silence_output { model.generate_qr_code('-', delivery_mode: :print) }
    end.to raise_error(WifiWand::QrCodeGenerationError, /Failed to generate QR code/)
  end

  it 'raises a targeted error before invoking qrencode when the output directory is missing' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'missing', 'wifi.png')

      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(File.dirname(filename))
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message).to include("output directory '#{File.dirname(filename)}' does not exist")
      }
    end
  end

  it 'raises a targeted error before invoking qrencode when the output directory is unwritable' do
    with_temp_dir do |temp_dir|
      output_dir = File.join(temp_dir, 'blocked')
      filename = File.join(output_dir, 'wifi.png')
      Dir.mkdir(output_dir)

      allow(File).to receive(:writable?).and_call_original
      allow(File).to receive(:writable?).with(output_dir).and_return(false)
      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(output_dir)
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message).to include("output directory '#{output_dir}' is not writable")
      }
    end
  end

  it 'raises a targeted error before invoking qrencode when the output path is a file' do
    with_temp_dir do |temp_dir|
      output_path = File.join(temp_dir, 'not-a-directory')
      filename = File.join(output_path, 'wifi.png')
      File.write(output_path, 'not a directory')

      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(output_path)
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message).to include("output path '#{output_path}' is not a directory")
      }
    end
  end

  it 'raises a targeted error when temp file staging fails after output directory preflight passes' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'wifi.png')
      staging_error = Errno::ENOSPC.new(temp_dir)

      expect(Tempfile).to receive(:create)
        .with(anything, temp_dir)
        .and_raise(staging_error)
      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(temp_dir)
        expect(error.source).to eq(staging_error)
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message)
          .to include("filesystem error while staging output in output directory '#{temp_dir}'")
        expect(error.message).to include(staging_error.message)
      }
    end
  end

  it 'uses provided password without querying system password' do
    provided_password = 'provided123'

    allow(model).to receive(:connection_security_type).and_return(nil)
    expect(model).not_to receive(:preferred_network_password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd).to include('-o')
      expect(staged_output_for(cmd)).to match(%r{\./TestNetwork-qr-code-.*\.png\z})
      expect(cmd.last).to include('T:WPA')
      expect(cmd.last).to include('P:provided123')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  [
    ['leading spaces with unknown security', '  provided123', nil],
    ['trailing spaces with unknown security', 'provided123  ', nil],
    ['an all-space WPA-length passphrase with unknown security', '        ', nil],
    ['an all-space WPA-length passphrase with known security', '        ', 'WPA2'],
  ].each do |description, provided_password, explicit_security|
    it "preserves #{description} in an explicit password" do
      allow(model).to receive(:connection_security_type).and_return(explicit_security)
      expect(model).not_to receive(:preferred_network_password)

      expect(model).to receive(:run_command) do |cmd|
        expect(cmd).to include('qrencode')
        expect(cmd.last).to eq("WIFI:T:WPA;S:TestNetwork;P:#{provided_password};H:false;;")
        command_result(stdout: '')
      end

      silence_output { model.generate_qr_code(nil, password: provided_password) }
    end
  end

  it 'looks up the connected network password through the model API when no password is provided' do
    expect(model).to receive(:preferred_network_password).with(ssid).and_return(password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('P:password123')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil) }
  end

  it 'uses WPA fallback when unknown security has a saved password' do
    allow(model).to receive(:connection_security_type).and_return(nil)
    allow(model).to receive(:preferred_network_password).with(ssid).and_return(password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('T:WPA')
      expect(cmd.last).to include('P:password123')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil) }
  end

  it 'does not look up a stored password for a confirmed open network' do
    allow(model).to receive(:connection_security_type).and_return('NONE')
    allow(model).to receive(:preferred_network_password)
      .with(ssid)
      .and_raise(WifiWand::PreferredNetworkNotFoundError.new(ssid))

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('T:nopass')
      expect(cmd.last).to include('P:')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil) }
    expect(model).not_to have_received(:preferred_network_password)
  end

  it 'omits an explicit password from a confirmed open network QR code' do
    allow(model).to receive(:connection_security_type).and_return('NONE')
    expect(model).not_to receive(:preferred_network_password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('T:nopass')
      expect(cmd.last).to include('P:;')
      expect(cmd.last).not_to include('ignored-password')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil, password: 'ignored-password') }
  end

  it 'raises a targeted error when unknown security has no saved preferred network' do
    allow(model).to receive(:connection_security_type).and_return(nil)
    allow(model).to receive(:preferred_network_password)
      .with(ssid)
      .and_raise(WifiWand::PreferredNetworkNotFoundError.new(ssid))

    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.generate_qr_code(nil) }
    end.to raise_error(
      WifiWand::QrCodeSecurityUndeterminedError,
      /security type could not be determined.*Pass the optional password argument/m
    )
  end

  it 'raises a targeted error when unknown security receives an empty explicit password' do
    allow(model).to receive(:connection_security_type).and_return(nil)
    allow(model).to receive(:preferred_network_password)
      .with(ssid)
      .and_raise(WifiWand::PreferredNetworkNotFoundError.new(ssid))

    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.generate_qr_code(nil, password: '') }
    end.to raise_error(WifiWand::QrCodeSecurityUndeterminedError)
  end

  it 'uses WPA fallback when unknown security receives a whitespace explicit password' do
    provided_password = " \t "

    allow(model).to receive(:connection_security_type).and_return(nil)
    expect(model).not_to receive(:preferred_network_password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to eq("WIFI:T:WPA;S:TestNetwork;P:#{provided_password};H:false;;")
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  it 'raises a targeted error when unknown security has a blank saved password' do
    allow(model).to receive(:connection_security_type).and_return(nil)
    allow(model).to receive(:preferred_network_password).with(ssid).and_return('')

    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.generate_qr_code(nil) }
    end.to raise_error(WifiWand::QrCodeSecurityUndeterminedError)
  end

  it 'raises a targeted error when a secured network has no saved password' do
    allow(model).to receive(:preferred_network_password).with(ssid).and_return(nil)

    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.generate_qr_code(nil) }
    end.to raise_error(WifiWand::QrCodePasswordUnavailableError, /Pass the optional password argument/)
  end

  [
    ['mixed whitespace with known security', "  saved \t password  ", 'WPA2'],
    ['an all-space WPA-length passphrase with unknown security', '        ', nil],
  ].each do |description, saved_password, saved_security|
    it "preserves #{description} in a saved password" do
      allow(model).to receive(:connection_security_type).and_return(saved_security)
      allow(model).to receive(:preferred_network_password).with(ssid).and_return(saved_password)

      expect(model).to receive(:run_command) do |cmd|
        expect(cmd).to include('qrencode')
        expect(cmd.last).to eq("WIFI:T:WPA;S:TestNetwork;P:#{saved_password};H:false;;")
        command_result(stdout: '')
      end

      silence_output { model.generate_qr_code(nil) }
    end
  end

  it 'raises a targeted error when a secured network is not in the preferred list' do
    allow(model).to receive(:preferred_network_password)
      .with(ssid)
      .and_raise(WifiWand::PreferredNetworkNotFoundError.new(ssid))

    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.generate_qr_code(nil) }
    end.to raise_error(WifiWand::QrCodePasswordUnavailableError, /Pass the optional password argument/)
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
      expect(model).to receive(:run_command) do |cmd|
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

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:false')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates QR code with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:true')
      command_result(stdout: '')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates ANSI QR with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..2]).to eq(%w[qrencode -t ANSI])
      expect(cmd.last).to include('H:true')
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = model.generate_qr_code('-')
    expect(out_stream.string).to include('[QR-ANSI]')
    expect(result).to eq('-')
  end

  # Overwrite behavior is covered in qr_overwrite_spec.rb
end
