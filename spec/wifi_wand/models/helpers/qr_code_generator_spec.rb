# frozen_string_literal: true

# QR Code Generator (unit)
# Verifies command construction without invoking external tools:
# - Render mode uses stdout and returns QR data
# - File mode renders data before staging output in a sibling temp file
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
  let(:err_stream) { StringIO.new }

  before do
    FileUtils.rm_f('TestNetwork-qr-code.png')
    FileUtils.rm_f('out.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
    model.verbose = false
    model.out_stream = out_stream
    model.err_stream = err_stream
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
    FileUtils.rm_f('out.png')
    FileUtils.rm_f('out.svg')
    FileUtils.rm_f('out.eps')
  end

  def with_temp_dir
    temp_dir = Dir.mktmpdir('qr_code_generator_test')
    yield temp_dir
  ensure
    FileUtils.rm_rf(temp_dir)
  end

  it 'renders ANSI QR string without printing' do
    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd[0..4]).to eq(%w[qrencode -t ANSI -o -])
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = model.render_qr_code(format: :ansi)
    expect(out_stream.string).to eq('')
    expect(result).to eq("[QR-ANSI]\n")
  end

  [
    { format: :png, type: 'PNG', output: "PNGDATA\x00".b },
    { format: :svg, type: 'SVG', output: '<svg></svg>' },
    { format: :eps, type: 'EPS', output: '%!PS-Adobe' },
  ].each do |tc|
    it "renders #{tc[:format]} QR data without printing" do
      expect(model).to receive(:run_command) do |*args|
        cmd = args.first
        options = args[1]

        expect(cmd).to be_an(Array)
        expect(cmd[0..4]).to eq(['qrencode', '-t', tc[:type], '-o', '-'])
        expect(options).to eq(log_stdout: false, binary_stdout: tc[:format] == :png)
        command_result(stdout: tc[:output])
      end

      result = model.render_qr_code(format: tc[:format])

      expect(result).to eq(tc[:output])
      expect(out_stream.string).to eq('')
    end
  end

  it 'raises ArgumentError for an unsupported render format' do
    expect(model).not_to receive(:command_available?)
    expect(model).not_to receive(:connected_network_name)
    expect(model).not_to receive(:run_command)

    expect do
      model.render_qr_code(format: :pdf)
    end.to raise_error(ArgumentError, 'unsupported QR render format: :pdf')
  end

  it 'raises ArgumentError for an unsupported file extension' do
    expect(model).not_to receive(:command_available?)
    expect(model).not_to receive(:run_command)

    expect do
      model.generate_qr_code('wifi.pdf')
    end.to raise_error(
      ArgumentError, 'unsupported QR output file extension: ".pdf". Use .png, .svg, or .eps.'
    )
  end

  it 'rejects hyphen as a library filespec' do
    expect(model).not_to receive(:run_command)

    expect do
      model.generate_qr_code('-')
    end.to raise_error(WifiWand::Error, /render_qr_code/)
  end

  it 'raises QrCodeGenerationError when ANSI generation command fails' do
    expect(model).to receive(:run_command)
      .and_raise(os_command_error(exitstatus: 1, command: 'qrencode', text: 'boom'))

    expect do
      silence_output { model.render_qr_code(format: :ansi) }
    end.to raise_error(WifiWand::QrCodeGenerationError, /Failed to generate QR code/)
  end

  [
    [:ubuntu, 'sudo apt install qrencode'],
    [:mac, 'brew install qrencode'],
    [:unknown, 'install qrencode using your system package manager'],
  ].each do |os_id, expected_command|
    it "raises a qrencode dependency error with #{expected_command.inspect} for #{os_id}" do
      allow(model).to receive(:command_available?).with('qrencode').and_return(false)
      allow(WifiWand::Platforms::Selector).to receive(:current_os).and_return(double('os', id: os_id))
      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.render_qr_code(format: :ansi) }
      end.to raise_error(WifiWand::Error, /#{Regexp.escape(expected_command)}/)
    end
  end

  it 'raises a targeted error when no WiFi network is connected' do
    allow(model).to receive(:connected_network_name).and_return(nil)
    expect(model).not_to receive(:run_command)

    expect do
      silence_output { model.render_qr_code(format: :ansi) }
    end.to raise_error(WifiWand::Error, /Not connected to any WiFi network/)
  end

  it 'raises a targeted error before dependency and network work when the output directory is missing' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'missing', 'wifi.png')
      in_stream = instance_double(IO, tty?: true)

      expect(in_stream).not_to receive(:gets)
      expect(model).not_to receive(:command_available?)
      expect(model).not_to receive(:connected_network_name)
      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename, in_stream: in_stream) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(File.dirname(filename))
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message).to include("output directory '#{File.dirname(filename)}' does not exist")
      }
    end
  end

  it 'validates the default output directory after building the default filename' do
    allow(model).to receive(:connected_network_name).and_return('DefaultNetwork')
    expect(model).to receive(:run_command)
      .with(
        satisfy { |cmd| cmd[0..4] == %w[qrencode -t PNG -o -] },
        log_stdout:    false,
        binary_stdout: true
      )
      .and_return(command_result(stdout: 'PNGDATA'))

    result = silence_output { model.generate_qr_code }

    expect(result).to eq('DefaultNetwork-qr-code.png')
    FileUtils.rm_f(result)
  end

  it 'validates the output directory before prompting for overwrite' do
    with_temp_dir do |temp_dir|
      parent_path = File.join(temp_dir, 'not-a-directory')
      filename = File.join(parent_path, 'wifi.png')
      in_stream = instance_double(IO, tty?: true)

      File.write(parent_path, 'not a directory')

      expect(in_stream).not_to receive(:gets)
      expect(model).not_to receive(:run_command)

      expect do
        silence_output { model.generate_qr_code(filename, in_stream: in_stream) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.directory).to eq(parent_path)
        expect(error.message).to include("output path '#{parent_path}' is not a directory")
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
      expect(Tempfile).not_to receive(:create)

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

  it 'raises a targeted error when an output directory becomes unwritable at write time' do
    with_temp_dir do |temp_dir|
      output_dir = File.join(temp_dir, 'blocked')
      filename = File.join(output_dir, 'wifi.png')
      write_error = Errno::EACCES.new(output_dir)
      Dir.mkdir(output_dir)

      expect(Tempfile).to receive(:create)
        .with(anything, output_dir)
        .and_raise(write_error)
      expect(model).to receive(:run_command)
        .with(satisfy { |cmd| cmd[0..4] == %w[qrencode -t PNG -o -] }, log_stdout: false, binary_stdout: true)
        .and_return(command_result(stdout: 'PNGDATA'))

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(output_dir)
        expect(error.source).to eq(write_error)
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message)
          .to include("filesystem error while writing output in output directory '#{output_dir}'")
        expect(error.message).to include(write_error.message)
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
      expect(model).to receive(:run_command)
        .with(satisfy { |cmd| cmd[0..4] == %w[qrencode -t PNG -o -] }, log_stdout: false, binary_stdout: true)
        .and_return(command_result(stdout: 'PNGDATA'))

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.filename).to eq(filename)
        expect(error.directory).to eq(temp_dir)
        expect(error.source).to eq(staging_error)
        expect(error.message).to include("Failed to write QR code output file '#{filename}'")
        expect(error.message)
          .to include("filesystem error while writing output in output directory '#{temp_dir}'")
        expect(error.message).to include(staging_error.message)
      }
    end
  end

  it 'uses provided password without querying system password' do
    provided_password = 'provided123'

    allow(model).to receive(:connection_security_type).and_return(nil)
    expect(model).not_to receive(:preferred_network_password)

    expect(model).to receive(:run_command) do |cmd, options|
      expect(cmd).to be_an(Array)
      expect(cmd[0..4]).to eq(%w[qrencode -t PNG -o -])
      expect(cmd.last).to include('T:WPA')
      expect(cmd.last).to include('P:provided123')
      expect(options).to eq(log_stdout: false, binary_stdout: true)
      command_result(stdout: 'PNGDATA')
    end

    silence_output { model.generate_qr_code(nil, password: provided_password) }
  end

  it 'writes rendered QR bytes through a staged temp file before rename' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'wifi.png')
      staged_tempfile = instance_double(Tempfile, path: File.join(temp_dir, 'staged'))

      expect(model).to receive(:run_command) do |cmd, options|
        expect(cmd[0..4]).to eq(%w[qrencode -t PNG -o -])
        expect(options).to eq(log_stdout: false, binary_stdout: true)
        command_result(stdout: "PNGDATA\x00".b)
      end
      expect(Tempfile).to receive(:create).with(anything, temp_dir).and_return(staged_tempfile)
      expect(staged_tempfile).to receive(:binmode).ordered
      expect(staged_tempfile).to receive(:write).with("PNGDATA\x00".b).ordered
      expect(staged_tempfile).to receive(:close).ordered
      expect(File).to receive(:rename).with(staged_tempfile.path, filename).ordered

      result = silence_output { model.generate_qr_code(filename) }

      expect(result).to eq(filename)
    end
  end

  it 'preserves the original write error when temp file cleanup also fails' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'wifi.png')
      temp_path = File.join(temp_dir, 'staged')
      staged_tempfile = instance_double(Tempfile, path: temp_path, closed?: true)
      rename_error = Errno::EACCES.new(filename)

      expect(model).to receive(:run_command)
        .with(satisfy { |cmd| cmd[0..4] == %w[qrencode -t PNG -o -] }, log_stdout: false, binary_stdout: true)
        .and_return(command_result(stdout: 'PNGDATA'))
      expect(Tempfile).to receive(:create).with(anything, temp_dir).and_return(staged_tempfile)
      expect(staged_tempfile).to receive(:binmode)
      expect(staged_tempfile).to receive(:write).with('PNGDATA')
      expect(staged_tempfile).to receive(:close)
      expect(File).to receive(:rename).with(temp_path, filename).and_raise(rename_error)
      allow(File).to receive(:exist?).and_call_original
      expect(File).to receive(:exist?).with(temp_path).and_return(true)
      expect(File).to receive(:delete).with(temp_path).and_raise(Errno::EACCES.new(temp_path))

      expect do
        silence_output { model.generate_qr_code(filename) }
      end.to raise_error(WifiWand::QrCodeOutputFileError) { |error|
        expect(error.source).to eq(rename_error)
        expect(error.message).to include(rename_error.message)
      }
    end
  end

  it 'does not report verbose output failures as QR file write failures' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'wifi.png')
      staged_tempfile = instance_double(Tempfile, path: File.join(temp_dir, 'staged'))
      output_error = Errno::EPIPE.new('closed output')

      model.verbose = true
      allow(err_stream).to receive(:puts).and_call_original
      expect(model).to receive(:run_command)
        .with(satisfy { |cmd| cmd[0..4] == %w[qrencode -t PNG -o -] }, log_stdout: false, binary_stdout: true)
        .and_return(command_result(stdout: 'PNGDATA'))
      expect(Tempfile).to receive(:create).with(anything, temp_dir).and_return(staged_tempfile)
      expect(staged_tempfile).to receive(:binmode).ordered
      expect(staged_tempfile).to receive(:write).with('PNGDATA').ordered
      expect(staged_tempfile).to receive(:close).ordered
      expect(File).to receive(:rename).with(staged_tempfile.path, filename).ordered
      expect(err_stream).to receive(:puts)
        .with("QR code generated: #{filename}")
        .ordered
        .and_raise(output_error)

      expect do
        model.generate_qr_code(filename)
      end.to raise_error(output_error.class)
    end
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
        command_result(stdout: 'PNGDATA')
      end

      silence_output { model.generate_qr_code(nil, password: provided_password) }
    end
  end

  it 'looks up the connected network password through the model API when no password is provided' do
    expect(model).to receive(:preferred_network_password).with(ssid).and_return(password)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('P:password123')
      command_result(stdout: 'PNGDATA')
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
      command_result(stdout: 'PNGDATA')
    end

    silence_output { model.generate_qr_code(nil) }
  end

  it 'maps WEP security into the WiFi QR payload' do
    allow(model).to receive(:connection_security_type).and_return('WEP')

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd.last).to eq('WIFI:T:WEP;S:TestNetwork;P:password123;H:false;;')
      command_result(stdout: 'PNGDATA')
    end

    silence_output { model.generate_qr_code(nil) }
  end

  it 'escapes all reserved WiFi QR field characters' do
    with_temp_dir do |temp_dir|
      filename = File.join(temp_dir, 'escaped.png')
      allow(model).to receive_messages(
        connected_network_name:     'Net;work,Name:With\\Slash',
        preferred_network_password: 'pass;word,name:with\\slash'
      )

      expect(model).to receive(:run_command) do |cmd|
        expect(cmd.last).to eq(
          'WIFI:T:WPA;S:Net\;work\,Name\:With\\\\Slash;P:pass\;word\,name\:with\\\\slash;H:false;;'
        )
        command_result(stdout: 'PNGDATA')
      end

      silence_output { model.generate_qr_code(filename) }
    end
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
      command_result(stdout: 'PNGDATA')
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
      command_result(stdout: 'PNGDATA')
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
    end.to raise_error(WifiWand::MacOsRedactionError, /Exact WiFi network identity.*wifiwand-macos-setup/)
  end

  [
    { filespec: 'out.png', type: 'PNG' },
    { filespec: 'out.svg', type: 'SVG' },
    { filespec: 'out.eps', type: 'EPS' },
  ].each do |tc|
    it "uses -t #{tc[:type]} flag when filespec ends with #{File.extname(tc[:filespec])}" do
      expect(model).to receive(:run_command) do |cmd, options|
        expect(cmd).to be_an(Array)
        expect(cmd).to include('qrencode')
        expect(cmd[0..4]).to eq(['qrencode', '-t', tc[:type], '-o', '-'])
        expect(options).to eq(log_stdout: false, binary_stdout: tc[:filespec].end_with?('.png'))
        command_result(stdout: "#{tc[:type]}DATA")
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
      command_result(stdout: 'PNGDATA')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'generates QR code with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command) do |cmd|
      expect(cmd).to be_an(Array)
      expect(cmd).to include('qrencode')
      expect(cmd.last).to include('H:true')
      command_result(stdout: 'PNGDATA')
    end

    silence_output { model.generate_qr_code('TestNetwork-qr-code.png') }
  end

  it 'renders ANSI QR with H:true for hidden networks' do
    allow(model).to receive(:network_hidden?).and_return(true)

    expect(model).to receive(:run_command) do |cmd, options|
      expect(cmd).to be_an(Array)
      expect(cmd[0..4]).to eq(%w[qrencode -t ANSI -o -])
      expect(cmd.last).to include('H:true')
      expect(options).to eq(log_stdout: false, binary_stdout: false)
      command_result(stdout: "[QR-ANSI]\n")
    end

    result = model.render_qr_code(format: :ansi)
    expect(out_stream.string).to eq('')
    expect(result).to eq("[QR-ANSI]\n")
  end

  # Overwrite behavior is covered in qr_overwrite_spec.rb
end
