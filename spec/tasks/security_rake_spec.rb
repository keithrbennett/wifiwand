# frozen_string_literal: true

require 'rake'
require 'tmpdir'
require_relative '../spec_helper'

RSpec.describe 'security rake tasks' do
  let(:temp_dir) { Dir.mktmpdir('wifiwand-security-rake-spec') }
  let(:invocations_path) { File.join(temp_dir, 'invocations') }
  let(:docs_audit_result) { :pass }

  # Stands in for `bundle` so the tasks' `sh` calls run without touching real audit databases.
  # Audit commands named in FAILING_AUDITS exit non-zero.
  let(:fake_bundle) do
    <<~SH
      #!/bin/sh
      echo "$2" >> "#{invocations_path}"
      case " $FAILING_AUDITS " in
        *" $2 "*) exit 1 ;;
      esac
      exit 0
    SH
  end

  around do |example|
    original_rake_application = Rake.application
    original_env = ENV.to_h.slice('PATH', 'FAILING_AUDITS')
    Rake.application = Rake::Application.new

    fake_bundle_path = File.join(temp_dir, 'bundle')
    File.write(fake_bundle_path, fake_bundle)
    File.chmod(0o755, fake_bundle_path)
    ENV['PATH'] = "#{temp_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}"
    ENV['FAILING_AUDITS'] = ''

    example.run
  ensure
    Rake.application = original_rake_application
    original_env.each { |key, value| ENV[key] = value }
    ENV.delete('FAILING_AUDITS') unless original_env.key?('FAILING_AUDITS')
    FileUtils.rm_rf(temp_dir)
  end

  before do
    result = docs_audit_result
    Rake::Task.define_task('docs:audit') { raise 'pip-audit reported vulnerabilities' if result == :fail }
    load File.expand_path('../../lib/tasks/security.rake', __dir__)
  end

  def invoked_audits
    File.readlines(invocations_path, chomp: true)
  end

  def run_security_all
    Rake::Task['security:all'].invoke
  end

  it 'runs every audit and reports success when all pass' do
    expect { run_security_all }.to output(/Security audits completed successfully/).to_stdout_from_any_process

    expect(invoked_audits).to eq(%w[bundle-audit ruby-audit])
  end

  it 'aborts naming the failed audit while still running the others' do
    ENV['FAILING_AUDITS'] = 'bundle-audit'

    expect { run_security_all }
      .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      .and output(/bundler-audit failed/).to_stderr_from_any_process

    expect(invoked_audits).to eq(%w[bundle-audit ruby-audit])
  end

  context 'when the documentation audit fails' do
    let(:docs_audit_result) { :fail }

    it 'aborts with a pip-audit failure after the Ruby audits ran' do
      expect { run_security_all }
        .to raise_error(SystemExit)
        .and output(/pip-audit failed: pip-audit reported vulnerabilities/).to_stderr_from_any_process

      expect(invoked_audits).to eq(%w[bundle-audit ruby-audit])
    end
  end
end
