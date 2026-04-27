# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../../../lib/wifi-wand/scripts/latest_ci_status'

RSpec.describe WifiWand::Scripts::LatestCiStatus do
  subject(:script) { described_class.new }

  let(:repository) { 'keithrbennett/wifiwand' }
  let(:success_status) { instance_double(Process::Status, success?: true) }
  let(:failure_status) { instance_double(Process::Status, success?: false) }
  let(:successful_run_json) do
    [{ databaseId: 123, status: 'completed', conclusion: 'success',
       url: 'https://github.com/example/repo/actions/runs/123', displayTitle: 'test', repository: repository,
       createdAt: '2026-04-27T12:00:00Z' }].to_json
  end
  let(:failed_run_json) do
    [{ databaseId: 456, status: 'completed', conclusion: 'failure',
       url: 'https://github.com/example/repo/actions/runs/456', displayTitle: 'test', repository: repository,
       createdAt: '2026-04-27T12:00:00Z' }].to_json
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
    allow(Kernel).to receive(:system).with('gh', 'run', 'view', '456', '--repo', repository, '--log-failed')

    expect { script.call }.to output(
      a_string_including('Fetching failure logs...')
    ).to_stdout
    expect(Kernel).to have_received(:system).with(
      'gh', 'run', 'view', '456', '--repo', repository, '--log-failed'
    )
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
