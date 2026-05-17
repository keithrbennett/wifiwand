# frozen_string_literal: true

require 'rake'
require_relative '../spec_helper'
require_relative '../../lib/wifi_wand/platforms/mac/helper/git_skip_worktree'

RSpec.describe 'swift:helper_skip tasks' do
  let(:skip_helper) { instance_double(WifiWand::Platforms::Mac::Helper::GitSkipWorktree) }

  around do |example|
    original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original_rake_application
  end

  before do
    allow(WifiWand::Platforms::Mac::Helper::GitSkipWorktree).to receive(:new).and_return(skip_helper)
    load File.expand_path('../../lib/tasks/swift.rake', __dir__)
  end

  it 'delegates start to the helper skip-worktree library' do
    expect(skip_helper).to receive(:start)

    Rake::Task['swift:helper_skip:start'].invoke
  end

  it 'delegates stop to the helper skip-worktree library' do
    expect(skip_helper).to receive(:stop)

    Rake::Task['swift:helper_skip:stop'].invoke
  end

  it 'delegates status to the helper skip-worktree library' do
    expect(skip_helper).to receive(:print_status)

    Rake::Task['swift:helper_skip:status'].invoke
  end
end
