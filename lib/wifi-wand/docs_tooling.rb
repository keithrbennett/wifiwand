# frozen_string_literal: true

module WifiWand
  module DocsTooling
    REPO_ROOT = File.expand_path('../..', __dir__)

    def self.venv_dir
      ENV.fetch('WIFIWAND_DOCS_VENV_DIR', File.join(REPO_ROOT, '.docs-venv'))
    end

    def self.venv_mkdocs_path
      File.join(venv_dir, 'bin', 'mkdocs')
    end

    def self.venv_pip_path
      File.join(venv_dir, 'bin', 'pip')
    end

    def self.build_script_path
      File.join(REPO_ROOT, 'bin', 'build-docs')
    end

    def self.build_script_command
      [build_script_path, build_script_path]
    end

    def self.start_server_script_path
      File.join(REPO_ROOT, 'bin', 'start-doc-server')
    end

    def self.start_server_script_command
      [start_server_script_path, start_server_script_path]
    end

    def self.requirements_path
      File.join(REPO_ROOT, 'requirements-lock.txt')
    end

    def self.mkdocs_config_path
      File.join(REPO_ROOT, 'mkdocs.yml')
    end

    def self.python_command
      ENV.fetch('WIFIWAND_DOCS_PYTHON', 'python3')
    end

    def self.executable?(command)
      if command.include?(File::SEPARATOR)
        File.file?(command) && File.executable?(command)
      else
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.file?(path) && File.executable?(path)
        end
      end
    end

    def self.mkdocs_command
      return venv_mkdocs_path if executable?(venv_mkdocs_path)

      'mkdocs'
    end

    def self.ensure_mkdocs_available!
      return if executable?(mkdocs_command)

      warn "Error: mkdocs not found. Run 'source bin/set-up-python-for-doc-server' or " \
        "'bundle exec rake docs:setup' first."
      exit 1
    end

    def self.ensure_python_available!
      return if executable?(python_command)

      warn "Error: Python executable \"#{python_command}\" not found."
      warn 'Install python3 or set WIFIWAND_DOCS_PYTHON to the Python executable path.'
      exit 1
    end

    def self.setup_environment!
      ensure_python_available!
      system(python_command, '-m', 'venv', venv_dir, exception: true)
      system(venv_pip_path, 'install', '-q', '-r', requirements_path, exception: true)
    end
  end
end
