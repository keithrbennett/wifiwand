# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require_relative '../../../lib/wifi-wand/scripts/latest_ci_status'

RSpec.describe WifiWand::Scripts::LatestCiStatus do
  subject(:script) { described_class.new }

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

  it 'prints the latest successful CI run for the current branch' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return([successful_run_json, '', success_status])

    expect { script.call }.to output(
      a_string_including(
        'Fetching latest CI run for branch: main...',
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
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--branch', 'feature/test', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return(['[]', '', success_status])

    expect { script.call }.to output(
      a_string_including(
        'Fetching latest CI run for branch: feature/test...',
        "No workflow runs found for branch 'feature/test'."
      )
    ).to_stdout
  end

  it 'fetches failed logs when the latest run failed' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return([failed_run_json, '', success_status])
    allow(Kernel).to receive(:system).with('gh', 'run', 'view', '456', '--log-failed')

    expect { script.call }.to output(
      a_string_including('Fetching failure logs...')
    ).to_stdout
    expect(Kernel).to have_received(:system).with('gh', 'run', 'view', '456', '--log-failed')
  end

  it 'aborts when gh run list fails' do
    allow(Open3).to receive(:capture3).with('git', 'rev-parse', '--abbrev-ref', 'HEAD').and_return(
      ['main', '', success_status]
    )
    allow(Open3).to receive(:capture3).with(
      'gh', 'run', 'list', '--branch', 'main', '--limit', '1', '--json',
      'databaseId,status,conclusion,url,displayTitle,createdAt'
    ).and_return(['', 'not authenticated', failure_status])

    expect { script.call }.to raise_error(SystemExit)
      .and output(
        a_string_including(
          "Failed to fetch runs. Ensure 'gh' is installed and you are authenticated."
        )
      ).to_stderr
  end
end
