# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/wifi-wand/docs_tooling'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe WifiWand::DocsTooling do
  let(:repo_root) { File.expand_path('../..', __dir__) }

  def with_executable(path, body = "#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def run_docs_script(script_name, chdir:)
    Dir.mktmpdir do |bin_dir|
      with_executable(File.join(bin_dir, 'mkdocs'), <<~SH)
        #!/bin/sh
        printf '%s\\n' "$@"
      SH

      env = {
        'PATH'                   => [bin_dir, ENV.fetch('PATH', '')].join(File::PATH_SEPARATOR),
        'WIFIWAND_DOCS_VENV_DIR' => File.join(bin_dir, 'no-docs-venv'),
      }
      script_path = File.join(repo_root, 'bin', script_name)
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, script_path, chdir: chdir)

      { stdout:, stderr:, exit_code: status.exitstatus }
    end
  end

  def with_env(overrides)
    saved = overrides.keys.to_h { |key| [key, ENV[key]] }
    overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV.store(key, value) }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV.store(key, value) }
  end

  describe 'repository-relative paths' do
    it 'resolves the virtual environment under the repository root' do
      with_env('WIFIWAND_DOCS_VENV_DIR' => nil) do
        expect(described_class.venv_dir).to eq(File.join(repo_root, '.docs-venv'))
      end
    end

    it 'allows the docs virtual environment path to be overridden' do
      Dir.mktmpdir('docs venv ') do |venv_dir|
        with_env('WIFIWAND_DOCS_VENV_DIR' => venv_dir) do
          expect(described_class.venv_dir).to eq(venv_dir)
        end
      end
    end

    it 'uses the locked requirements file as the dependency source' do
      expect(described_class.requirements_path).to eq(File.join(repo_root, 'requirements-lock.txt'))
    end

    it 'resolves the MkDocs config under the repository root' do
      expect(described_class.mkdocs_config_path).to eq(File.join(repo_root, 'mkdocs.yml'))
    end

    it 'resolves the build script under the repository root' do
      expect(described_class.build_script_path).to eq(File.join(repo_root, 'bin', 'build-docs'))
    end

    it 'builds a Rake shell-safe command array for the build script' do
      expect(described_class.build_script_command).to eq([
        described_class.build_script_path,
        described_class.build_script_path,
      ])
    end

    it 'resolves the start-server script under the repository root' do
      expect(described_class.start_server_script_path).to eq(File.join(repo_root, 'bin', 'start-doc-server'))
    end

    it 'builds a Rake shell-safe command array for the start-server script' do
      expect(described_class.start_server_script_command).to eq([
        described_class.start_server_script_path,
        described_class.start_server_script_path,
      ])
    end
  end

  describe '.executable?' do
    it 'accepts executable paths that contain spaces' do
      Dir.mktmpdir('docs tooling ') do |dir|
        command_path = File.join(dir, 'mk docs')
        with_executable(command_path)

        expect(described_class.executable?(command_path)).to be true
      end
    end

    it 'treats shell metacharacters as literal path characters' do
      sentinel = '/tmp/docs_tooling_injection_test'
      FileUtils.rm_f(sentinel)

      expect(described_class.executable?("/no/such/mkdocs; touch #{sentinel}")).to be false
      expect(File.exist?(sentinel)).to be false
    end
  end

  describe '.mkdocs_command' do
    it 'prefers the repository virtual environment when its mkdocs executable exists' do
      venv_mkdocs = File.join(repo_root, '.docs-venv', 'bin', 'mkdocs')

      allow(described_class).to receive(:executable?).with(venv_mkdocs).and_return(true)

      expect(described_class.mkdocs_command).to eq(venv_mkdocs)
    end

    it 'falls back to PATH lookup when the repository virtual environment is unavailable' do
      allow(described_class).to receive(:executable?).with(described_class.venv_mkdocs_path).and_return(false)

      expect(described_class.mkdocs_command).to eq('mkdocs')
    end
  end

  describe '.python_command' do
    it 'defaults to python3' do
      with_env('WIFIWAND_DOCS_PYTHON' => nil) do
        expect(described_class.python_command).to eq('python3')
      end
    end

    it 'can be overridden for environments with a non-default Python executable' do
      with_env('WIFIWAND_DOCS_PYTHON' => '/opt/python/bin/python') do
        expect(described_class.python_command).to eq('/opt/python/bin/python')
      end
    end
  end

  describe '.ensure_python_available!' do
    it 'exits with setup guidance when the configured Python executable is unavailable' do
      allow(described_class).to receive(:executable?).with('missing-python').and_return(false)

      with_env('WIFIWAND_DOCS_PYTHON' => 'missing-python') do
        expect do
          expect { described_class.ensure_python_available! }.to raise_error(SystemExit) do |error|
            expect(error.status).to eq(1)
          end
        end.to output(/set WIFIWAND_DOCS_PYTHON/).to_stderr
      end
    end
  end

  describe '.setup_environment!' do
    it 'creates the repo virtual environment and installs locked dependencies' do
      allow(described_class).to receive(:ensure_python_available!)
      allow(described_class).to receive(:python_command).and_return('/usr/bin/python3')

      expect(described_class).to receive(:system).with(
        '/usr/bin/python3',
        '-m',
        'venv',
        described_class.venv_dir,
        exception: true
      ).ordered
      expect(described_class).to receive(:system).with(
        described_class.venv_pip_path,
        'install',
        '-q',
        '-r',
        described_class.requirements_path,
        exception: true
      ).ordered

      described_class.setup_environment!
    end
  end

  describe 'bin/build-docs' do
    it 'uses the repository MkDocs config when launched outside the repository root' do
      Dir.mktmpdir('docs cwd ') do |chdir|
        result = run_docs_script('build-docs', chdir: chdir)

        expect(result[:exit_code]).to eq(0)
        expect(result[:stderr]).to eq('')
        expect(result[:stdout]).to include('build')
        expect(result[:stdout]).to include('--strict')
        expect(result[:stdout]).to include(described_class.mkdocs_config_path)
      end
    end
  end

  describe 'bin/start-doc-server' do
    it 'uses the repository MkDocs config when launched outside the repository root' do
      Dir.mktmpdir('docs cwd ') do |chdir|
        result = run_docs_script('start-doc-server', chdir: chdir)

        expect(result[:exit_code]).to eq(0)
        expect(result[:stderr]).to eq('')
        expect(result[:stdout]).to include('Starting documentation server...')
        expect(result[:stdout]).to include('serve')
        expect(result[:stdout]).to include(described_class.mkdocs_config_path)
      end
    end
  end

  describe 'bin/set-up-python-for-doc-server' do
    it 'requires sourcing and prints both usage forms to stderr' do
      script_path = File.join(repo_root, 'bin', 'set-up-python-for-doc-server')
      stdout, stderr, status = Open3.capture3('bash', script_path)

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq('')
      expect(stderr).to include('Error: This script must be sourced, not executed directly.')
      expect(stderr).to include('Usage: source bin/set-up-python-for-doc-server')
      expect(stderr).to include('or: . bin/set-up-python-for-doc-server')
    end

    it 'returns before activation when setup fails while sourced' do
      Dir.mktmpdir('docs setup ') do |tmpdir|
        venv_dir = File.join(tmpdir, 'venv')
        command = [
          "export WIFIWAND_DOCS_VENV_DIR=#{venv_dir.inspect}",
          "export WIFIWAND_DOCS_PYTHON=#{File.join(tmpdir, 'missing-python').inspect}",
          "source #{File.join(repo_root, 'bin', 'set-up-python-for-doc-server').inspect}",
          'printf "after:%s\\n" "$?"',
        ].join("\n")

        stdout, stderr, status = Open3.capture3('bash', '-lc', command)

        expect(status.exitstatus).to eq(0)
        expect(stdout).to include('after:1')
        expect(stdout).not_to include('Documentation environment ready.')
        expect(stderr).to include('set WIFIWAND_DOCS_PYTHON')
      end
    end
  end
end
