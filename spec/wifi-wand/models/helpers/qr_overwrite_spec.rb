# frozen_string_literal: true

# QR Code Overwrite Confirmation (unit)
# Exercises overwrite branches without calling external tools:
# - overwrite: true preserves the existing file until replacement succeeds
# - interactive TTY yes/no
# - non-interactive error guidance

require_relative '../../../spec_helper'
require 'fileutils'
require 'tmpdir'

describe 'QR Code Overwrite Confirmation' do
  let(:model) { create_test_model }
  let(:ssid) { 'TestNetwork' }
  let(:password) { 'password123' }
  let(:security) { 'WPA2' }
  let(:out_stream) { StringIO.new }

  before do
    # Stub environment and dependencies
    model.instance_variable_set(:@original_out_stream, out_stream)
    allow(model).to receive(:command_available?).with('qrencode').and_return(true)
    allow(model).to receive_messages(
      connected_network_name:     ssid,
      connection_security_type:   security,
      connected_network_password: password,
      network_hidden?:            false
    )
  end

  # Helper to manage temp directory lifecycle
  def with_temp_file
    temp_dir = Dir.mktmpdir('qr_overwrite_test')
    filename = File.join(temp_dir, 'TestNetwork-qr-code.png')
    begin
      yield(filename)
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  def qrencode_command_for(filename)
    satisfy do |cmd|
      cmd.is_a?(Array) &&
        cmd.first == 'qrencode' &&
        cmd.include?('-o') &&
        cmd[cmd.index('-o') + 1] != filename
    end
  end

  def staged_output_for(cmd)
    cmd[cmd.index('-o') + 1]
  end

  it 'prompts and replaces the file after successful regeneration' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      in_stream = instance_double(IO, tty?: true, gets: "y\n")
      expect(File).to receive(:rename).with(kind_of(String), filename).and_call_original
      expect(model).to receive(:run_os_command).with(qrencode_command_for(filename)) do |cmd|
        staged_filename = staged_output_for(cmd)

        expect(File.exist?(filename)).to be true
        expect(File.read(filename)).to eq('old')

        File.write(staged_filename, 'new')
        command_result(stdout: '')
      end

      result = silence_output { model.generate_qr_code(filename, in_stream: in_stream) }

      expect(result).to eq(filename)
      expect(File.read(filename)).to eq('new')
      expect(out_stream.string).to eq('Output file exists. Overwrite? [y/N]: ')
    end
  end

  it 'prompts and aborts when user declines overwrite' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      in_stream = instance_double(IO, tty?: true, gets: "n\n")

      expect(model).not_to receive(:run_os_command)

      expect do
        silence_output { model.generate_qr_code(filename, in_stream: in_stream) }
      end.to raise_error(WifiWand::Error, /cancelled: file exists/i)
      expect(File.read(filename)).to eq('old')
      expect(out_stream.string).to eq('Output file exists. Overwrite? [y/N]: ')
    end
  end

  it 'errors in non-interactive mode when file exists' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      in_stream = instance_double(IO, tty?: false)

      expect(model).not_to receive(:run_os_command)

      expect do
        silence_output { model.generate_qr_code(filename, in_stream: in_stream) }
      end.to raise_error(WifiWand::Error, /already exists.*Delete the file first/i)
      expect(File.read(filename)).to eq('old')
      expect(out_stream.string).to eq('')
    end
  end

  it 'replaces the existing file after successful overwrite: true regeneration' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      expect(File).to receive(:rename).with(kind_of(String), filename).and_call_original
      expect(model).to receive(:run_os_command).with(qrencode_command_for(filename)) do |cmd|
        staged_filename = staged_output_for(cmd)

        expect(File.exist?(filename)).to be true
        expect(File.read(filename)).to eq('old')

        File.write(staged_filename, 'new')
        command_result(stdout: '')
      end

      result = silence_output { model.generate_qr_code(filename, overwrite: true) }

      expect(result).to eq(filename)
      expect(File.read(filename)).to eq('new')
    end
  end

  it 'preserves the existing file when qrencode fails during overwrite: true regeneration' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      expect(model).to receive(:run_os_command).with(qrencode_command_for(filename)) do |cmd|
        staged_filename = staged_output_for(cmd)

        expect(File.exist?(filename)).to be true
        expect(File.read(filename)).to eq('old')

        File.write(staged_filename, 'partial')
        raise WifiWand::CommandExecutor::OsCommandError.new(1, cmd.join(' '), 'boom')
      end
      expect(File).not_to receive(:rename)

      expect do
        silence_output { model.generate_qr_code(filename, overwrite: true) }
      end.to raise_error(WifiWand::Error, /Failed to generate QR code/)
      expect(File.read(filename)).to eq('old')
    end
  end

  it 'preserves the existing file when qrencode fails after interactive confirmation' do
    with_temp_file do |filename|
      File.write(filename, 'old')

      in_stream = instance_double(IO, tty?: true, gets: "y\n")
      expect(model).to receive(:run_os_command).with(qrencode_command_for(filename)) do |cmd|
        staged_filename = staged_output_for(cmd)

        expect(File.exist?(filename)).to be true
        expect(File.read(filename)).to eq('old')

        File.write(staged_filename, 'partial')
        raise WifiWand::CommandExecutor::OsCommandError.new(1, cmd.join(' '), 'boom')
      end
      expect(File).not_to receive(:rename)

      expect do
        silence_output { model.generate_qr_code(filename, in_stream: in_stream) }
      end.to raise_error(WifiWand::Error, /Failed to generate QR code/)
      expect(File.read(filename)).to eq('old')
    end
  end
end
