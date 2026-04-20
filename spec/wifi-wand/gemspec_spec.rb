# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'wifi-wand.gemspec packaging' do
  subject(:packaged_files) do
    Gem::Specification.load(File.expand_path('../../wifi-wand.gemspec', __dir__)).files.sort
  end

  it 'includes runtime executables, code, assets, and user-facing docs needed by gem consumers' do
    expect(packaged_files).to include(
      'README.md',
      'docs/MACOS_SETUP.md',
      'docs/CHANGELOG_V2_TO_V3.md',
      'docs/BREAKING_CHANGES_V3.md',
      'exe/wifi-wand',
      'exe/wifi-wand-macos-setup',
      'lib/wifi-wand/mac_helper/mac_os_wifi_auth_helper.rb',
      'lib/wifi-wand/mac_helper/swift/WifiNetworkConnector.swift',
      'lib/wifi-wand/mac_helper/swift/WifiNetworkDisconnector.swift',
      'libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper'
    )
  end

  it 'excludes maintainer-only tooling, helper build inputs, and non-shipping test docs' do
    expect(packaged_files).not_to include(
      'bin/mac-helper',
      'bin/op-wrap',
      'bin/setup-hooks',
      'docs/TESTING.md',
      'lib/wifi-wand/mac_helper/mac_helper_release.rb',
      'libexec/macos/src/wifiwand-helper.swift',
      'libexec/macos/wifiwand-helper.entitlements',
      'libexec/macos/wifiwand-helper.source-manifest.json',
      'spec/wifi-wand/mac_helper/mac_helper_release_spec.rb'
    )
    expect(packaged_files.grep(%r{\Abin/})).to be_empty
    expect(packaged_files.grep(%r{\Alib/tasks/})).to be_empty
    expect(packaged_files.grep(%r{\Aspec/})).to be_empty
  end
end
