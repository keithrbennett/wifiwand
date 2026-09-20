# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../../../lib/wifi_wand/scripts/latest_ci_status'

RSpec.describe WifiWand::Scripts::LatestCiStatus do
  subject(:script) { described_class.new }

  let(:repository) { 'keithrbennett/wifiwand' }
  let(:pager_disabled_env) do
    {
      'GH_PAGER'  => 'cat',
      'PAGER'     => 'cat',
      'GIT_PAGER' => 'cat',
    }
  end
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }
  let(:successful_run_json) do
    [{ databaseId: 123, status: 'completed', conclusion: 'success',
       url: 'https://github.com/example/repo/actions/runs/123', displayTitle: 'test',
       createdAt: '2026-04-27T12:00:00Z' }].to_json
  end
  let(:failed_run_json) do
    [{ databaseId: 456, status: 'completed', conclusion: 'failure',
       url: 'https://github.com/example/repo/actions/runs/456', displayTitle: 'test',
       createdAt: '2026-04-27T12:00:00Z' }].to_json
  end

  describe 'repository parsing' do
    {
      'git@github.com:keithrbennett/wifiwand.git'       => 'keithrbennett/wifiwand',
      'https://github.com/keithrbennett/wifiwand.git'   => 'keithrbennett/wifiwand',
      'ssh://git@github.com/keithrbennett/wifiwand.git' => 'keithrbennett/wifiwand',
    }.each do |remote_url, expected_repository|
      it "accepts #{remote_url}" do
        expect(script.send(:parse_github_repository, remote_url)).to eq(expected_repository)
      end
    end

    it 'rejects non-GitHub remotes' do
      remote_url = 'ssh://git@example.com/keithrbennett/wifiwand.git'

      expect { script.send(:parse_github_repository, remote_url) }.to raise_error(SystemExit)
        .and output(
          a_string_including("Unable to determine GitHub repository from origin remote: #{remote_url}")
        ).to_stderr
    end
  end

  it 'prints the latest successful CI run for the current branch' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
      ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return([successful_run_json, '', success_status])

    expect { script.call }.to output(
      a_string_including(
        'Fetching latest CI run for branch: main...',
        "Repository: #{repository}",
        'Latest Run Details:',
        'Title:      test',
        'ID:         123',
        'Time:       2026-04-27T12:00:00Z',
        "\e[32mSUCCESS\e[0m"
      )
    ).to_stdout
  end

  it 'prints a no-runs message when GitHub Actions has no runs for the branch' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['feature/test', '', success_status]
    )
    allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
      ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--repo', repository, '--branch', 'feature/test', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return(['[]', '', success_status])
    allow(Open3).to receive(:capture3).with(
      'gh', 'api', 'repos/keithrbennett/wifiwand/actions/runs?branch=feature%2Ftest&per_page=1'
    ).and_return([{ workflow_runs: [] }.to_json, '', success_status])

    expect { script.call }.to output(
      a_string_including(
        'Fetching latest CI run for branch: feature/test...',
        "Repository: #{repository}",
        "No workflow runs found for branch 'feature/test'."
      )
    ).to_stdout
  end

  it 'falls back to the Actions API when gh run list returns an empty array' do
    api_response = {
      workflow_runs: [
        {
          id:            789,
          status:        'completed',
          conclusion:    'success',
          html_url:      'https://github.com/example/repo/actions/runs/789',
          display_title: 'api fallback run',
          created_at:    '2026-04-27T18:00:00Z',
          repository:    { full_name: repository },
        },
      ],
    }.to_json

    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
      ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return(['[]', '', success_status])
    allow(Open3).to receive(:capture3).with(
      'gh', 'api', 'repos/keithrbennett/wifiwand/actions/runs?branch=main&per_page=1'
    ).and_return([api_response, '', success_status])

    expect { script.call }.to output(
      a_string_including(
        'Latest Run Details:',
        'Title:      api fallback run',
        'ID:         789'
      )
    ).to_stdout
  end

  it 'fetches failed logs when the latest run failed' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
      ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return([failed_run_json, '', success_status])
    allow(Kernel).to receive(:system).with(
      pager_disabled_env,
      'gh', 'run', 'view', '456', '--repo', repository, '--log-failed',
      hash_including(out: an_instance_of(StringIO), err: $stderr)
    )

    expect { script.call }.to output(
      a_string_including('Fetching failure logs...')
    ).to_stdout
    expect(Kernel).to have_received(:system).with(
      pager_disabled_env,
      'gh', 'run', 'view', '456', '--repo', repository, '--log-failed',
      hash_including(out: an_instance_of(StringIO), err: $stderr)
    )
  end

  describe 'status display' do
    def run_json(status:, conclusion: nil)
      [{ databaseId: 321, status: status, conclusion: conclusion, url: 'https://example.test/runs/321',
         displayTitle: 'status test', createdAt: '2026-04-27T12:00:00Z' }].to_json
    end

    def stub_latest_run(json)
      allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
        ['main', '', success_status]
      )
      allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
        ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
      )
      allow(Open3).to receive(:capture3).with(
        'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
        'databaseId,status,conclusion,url,displayTitle,createdAt'
      ).and_return([json, '', success_status])
    end

    it 'shows how to watch a run that is in progress' do
      stub_latest_run(run_json(status: 'in_progress'))

      expect { script.call }.to output(
        a_string_including("\e[34mIN_PROGRESS\e[0m", 'Build is currently running...',
          'gh run watch 321')
      ).to_stdout
    end

    it 'reports a queued run' do
      stub_latest_run(run_json(status: 'queued'))

      expect { script.call }.to output(
        a_string_including("\e[34mQUEUED\e[0m", 'Build is queued...')
      ).to_stdout
    end

    it 'colors a cancelled run yellow without fetching logs' do
      stub_latest_run(run_json(status: 'completed', conclusion: 'cancelled'))
      allow(Kernel).to receive(:system)

      expect { script.call }.to output(a_string_including("\e[33mCANCELLED\e[0m")).to_stdout
      expect(Kernel).not_to have_received(:system)
    end

    it 'colors other conclusions white' do
      stub_latest_run(run_json(status: 'completed', conclusion: 'skipped'))

      expect { script.call }.to output(a_string_including("\e[37mSKIPPED\e[0m")).to_stdout
    end

    it 'shows UNKNOWN when a completed run has no conclusion' do
      stub_latest_run(run_json(status: 'completed', conclusion: nil))

      expect { script.call }.to output(a_string_including("\e[37mUNKNOWN\e[0m")).to_stdout
    end
  end

  describe 'error handling' do
    it 'aborts when the Actions API fallback fails' do
      allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
        ['main', '', success_status]
      )
      allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
        ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
      )
      allow(Open3).to receive(:capture3).with(
        'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
        'databaseId,status,conclusion,url,displayTitle,createdAt'
      ).and_return(['[]', '', success_status])
      allow(Open3).to receive(:capture3).with(
        'gh', 'api', 'repos/keithrbennett/wifiwand/actions/runs?branch=main&per_page=1'
      ).and_return(['', 'HTTP 403', failure_status])

      expect { script.call }.to raise_error(SystemExit)
        .and output(
          a_string_including('Failed to fetch runs from the Actions API', 'HTTP 403')
        ).to_stderr
    end

    it 'aborts when gh run list output is not valid JSON' do
      expect { script.send(:parse_run_list_response, 'not json') }.to raise_error(SystemExit)
        .and output(a_string_including('Unable to parse gh run list output')).to_stderr
    end

    it 'aborts when the Actions API output is not valid JSON' do
      expect { script.send(:parse_actions_api_response, 'not json') }.to raise_error(SystemExit)
        .and output(a_string_including('Unable to parse GitHub Actions API output')).to_stderr
    end

    it 'aborts with the command and stderr when a required command fails' do
      allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
        ['', 'fatal: not a git repository', failure_status]
      )

      expect { script.call }.to raise_error(SystemExit)
        .and output(
          a_string_including('Error running: git rev-parse --abbrev-ref HEAD',
            'fatal: not a git repository')
        ).to_stderr
    end

    it 'aborts with a clear message when a required command is not installed' do
      allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD')
        .and_raise(Errno::ENOENT)

      expect { script.call }.to raise_error(SystemExit)
        .and output(a_string_including('ERROR: Command not found: git rev-parse --abbrev-ref HEAD'))
        .to_stderr
    end

    it 'reports a missing gh executable as a failed response rather than raising' do
      allow(Open3).to receive(:capture3).with('gh', 'api', 'x').and_raise(Errno::ENOENT)

      response = script.send(:run_command_with_status, %w[gh api x])

      expect(response).to eq(stdout: '', stderr: 'Command not found: gh api x', success: false)
    end
  end

  describe 'command helpers' do
    it 'passes a string command to Open3 as a single argument' do
      allow(Open3).to receive(:capture3).with('git status').and_return(['ok', '', success_status])

      expect(script.send(:run_command, 'git status')).to eq('ok')
    end

    it 'formats string commands for display unchanged' do
      expect(script.send(:command_display, 'git status')).to eq('git status')
    end

    it 'shell-escapes array commands for display' do
      expect(script.send(:command_display, ['echo', 'a b'])).to eq('echo a\\ b')
    end
  end

  it 'aborts when gh run list fails' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with('git', 'remote', 'get-url', 'origin').and_return(
      ['git@github.com:keithrbennett/wifiwand.git', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--repo', repository, '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return(['', 'not authenticated', failure_status])

    expect { script.call }.to raise_error(SystemExit)
      .and output(
        a_string_including(
          "Failed to fetch runs. Ensure 'gh' is installed and you are authenticated.",
          'not authenticated'
        )
      ).to_stderr
  end
end
