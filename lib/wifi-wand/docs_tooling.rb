# frozen_string_literal: true

require 'shellwords'

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

    def self.start_server_script_path
      File.join(REPO_ROOT, 'bin', 'start-doc-server')
    end

    def self.setup_script_path
      File.join(REPO_ROOT, 'bin', 'set-up-python-for-doc-server')
    end

    def self.rakefile_path
      File.join(REPO_ROOT, 'Rakefile')
    end

    def self.gemfile_path
      File.join(REPO_ROOT, 'Gemfile')
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
      mkdocs_override = ENV.fetch('WIFIWAND_DOCS_MKDOCS', '').strip
      return mkdocs_override unless mkdocs_override.empty?

      return venv_mkdocs_path if executable?(venv_mkdocs_path)

      'mkdocs'
    end

    def self.rake_passthrough_args
      @rake_passthrough_args ||= extract_rake_passthrough_args!
    end

    def self.extract_rake_passthrough_args!(argv = ARGV, rake_application = Rake.application)
      separator_index = argv.index('--')
      return [] unless separator_index

      args = argv[(separator_index + 1)..]
      argv.slice!(separator_index..)
      rake_application.top_level_tasks.replace(argv.dup)
      args
    end

    def self.setup_guidance
      source_command = "source #{setup_script_path.shellescape}"
      rake_command = "BUNDLE_GEMFILE=#{gemfile_path.shellescape} bundle exec rake -f " \
        "#{rakefile_path.shellescape} docs:setup"

      [source_command, rake_command]
    end

    def self.ensure_mkdocs_available!
      return if executable?(mkdocs_command)

      source_command, rake_command = setup_guidance

      warn 'Error: mkdocs not found. Set up the documentation environment first:'
      warn "  #{source_command}"
      warn 'or:'
      warn "  #{rake_command}"
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
