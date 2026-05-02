# frozen_string_literal: true

require 'shellwords'
require 'fileutils'
require 'pathname'
require 'yaml'

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

    def self.generated_docs_dir
      File.join(REPO_ROOT, 'tmp', "mkdocs-src-#{Process.pid}")
    end

    def self.generated_config_path
      File.join(REPO_ROOT, 'tmp', "mkdocs-#{Process.pid}.yml")
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
      task_like_args = args.reject { |arg| arg.start_with?('-') }
      rake_application.top_level_tasks.reject! { |task| task_like_args.include?(task) }
      args
    end

    def self.prepare_mkdocs_workspace!
      FileUtils.rm_rf(generated_docs_dir)
      FileUtils.mkdir_p(generated_docs_dir)

      copy_docs_source('README.md')
      copy_docs_source('RELEASE_NOTES.md')
      copy_docs_source('LICENSE.txt')
      copy_docs_source('Gemfile')
      copy_docs_tree('lib')
      copy_docs_tree('spec')
      copy_docs_tree('docs', exclude: ['index.md'])
      copy_docs_tree('dev/docs')
      copy_docs_tree('dev/reports', required: false)
      copy_docs_tree('dev/prompts', required: false)
      copy_docs_tree('logo', required: false)
      rewrite_generated_markdown_links
      write_generated_config

      generated_config_path
    end

    def self.copy_docs_source(relative_path)
      source = File.join(REPO_ROOT, relative_path)
      return unless File.exist?(source)

      destination = File.join(generated_docs_dir, relative_path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
    end

    def self.copy_docs_tree(relative_path, exclude: [], required: true)
      source = File.join(REPO_ROOT, relative_path)
      return unless required_docs_tree_exists?(source, relative_path, required)

      destination = File.join(generated_docs_dir, relative_path)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp_r(source, File.dirname(destination))

      exclude.each do |excluded_file|
        FileUtils.rm_f(File.join(destination, excluded_file))
      end
    end

    def self.required_docs_tree_exists?(source, relative_path, required)
      return true if File.directory?(source)
      return false unless required

      raise "Required documentation source directory is missing: #{relative_path}"
    end

    def self.write_generated_config
      config = YAML.load_file(mkdocs_config_path)
      config['docs_dir'] = generated_docs_dir
      config['site_dir'] = File.join(REPO_ROOT, 'site')
      config['exclude_docs'] = generated_exclude_docs(config['exclude_docs'])
      config['nav'] = generated_nav(config['nav'])

      FileUtils.mkdir_p(File.dirname(generated_config_path))
      File.write(generated_config_path, config.to_yaml)
    end

    def self.generated_nav(nav)
      nav.map do |entry|
        case entry
        when Hash
          entry.transform_values { |value| value == 'index.md' ? 'README.md' : value }
        else
          entry
        end
      end
    end

    def self.rewrite_generated_markdown_links
      Dir.glob(File.join(generated_docs_dir, '**', '*.md')).each do |markdown_path|
        markdown = File.read(markdown_path)
        rewritten = markdown.gsub(%r{\((#{Regexp.escape(REPO_ROOT)}/[^)\s]+?)(?::\d+)?\)}) do
          generated_relative_link(Regexp.last_match(1), markdown_path)
        end
        rewritten = rewrite_excluded_generated_links(rewritten, markdown_path)
        File.write(markdown_path, rewritten) if rewritten != markdown
      end
    end

    def self.generated_relative_link(absolute_target, markdown_path)
      repo_relative_target = absolute_target.delete_prefix("#{REPO_ROOT}/")
      generated_target = File.join(generated_docs_dir, repo_relative_target)
      return "(#{absolute_target})" unless File.exist?(generated_target)

      generated_target = directory_index_path(generated_target) if File.directory?(generated_target)
      relative_target = Pathname
        .new(generated_target)
        .relative_path_from(Pathname.new(File.dirname(markdown_path)))
        .to_s
      "(#{relative_target})"
    end

    def self.directory_index_path(directory)
      index_path = File.join(directory, 'index.md')
      return index_path if File.exist?(index_path)

      entries = Dir
        .children(directory)
        .reject { |entry| entry.start_with?('.') }
        .sort
      body = ["# #{File.basename(directory)}", '', *entries.map { |entry| "- `#{entry}`" }, ''].join("\n")
      File.write(index_path, body)
      index_path
    end

    def self.rewrite_excluded_generated_links(markdown, markdown_path)
      markdown.gsub(%r{\[([^\]]+)\]\(([^)\s]+)\)}) do
        label = Regexp.last_match(1)
        target = Regexp.last_match(2)
        excluded_generated_link?(target, markdown_path) ? label : Regexp.last_match(0)
      end
    end

    def self.excluded_generated_link?(target, markdown_path)
      target_path = target.split('#', 2).first
      return false if target_path.empty? || target_path.match?(%r{\A[a-z][a-z0-9+.-]*:}i)

      absolute_target = File.expand_path(target_path, File.dirname(markdown_path))
      repo_relative_target = Pathname
        .new(absolute_target)
        .relative_path_from(Pathname.new(generated_docs_dir))
        .to_s
      %w[dev/reports dev/prompts].any? do |prefix|
        repo_relative_target == prefix || repo_relative_target.start_with?("#{prefix}/")
      end
    end

    def self.generated_exclude_docs(exclude_docs)
      exclude_docs
        .to_s
        .lines
        .reject { |line| %w[lib/ spec/].include?(line.strip) }
        .join
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
