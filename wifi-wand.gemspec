# frozen_string_literal: true

# Extract the version string from lib/wifi_wand/version.rb so it remains the
# single source of truth and doesn't need to be duplicated here.  MatchData[0]
# is the full match (e.g. VERSION = "1.2.3"), [1] is the first capture group
# (the version string alone).
version = -> {
  source = File.read(File.expand_path('lib/wifi_wand/version.rb', __dir__))
  source.match(/\bVERSION\s*=\s*['"]([^'"]+)['"]/)&.[](1)
}.call
raise 'Could not read wifi-wand version from lib/wifi_wand/version.rb' unless version

# Whitelist of glob patterns for files to include in the built gem.  Only files
# matching at least one of these are eligible; they may still be removed by the
# exclusion list below.
packaged_file_patterns = [
  'LICENSE.txt',
  'README.md',
  'RELEASE_NOTES.md',
  'docs/**/*.md',
  'exe/*',
  'lib/**/*.rb',
  'lib/wifi_wand/platforms/mac/helper/swift/*.swift',
  'lib/**/*.yml',
  'libexec/**/*',
].freeze

# Exclusion list (regexps matched against each file path).  These remove
# maintainer-only tooling and build artifacts that happen to match the
# whitelist globs above.
excluded_packaged_files = [
  %r{\Adocs/(?:ai-reports|dev)/},                                  # AI / developer-only doc directories
  %r{\Alib/tasks/},                                                # rake tasks (not needed at runtime)
  %r{\Alib/wifi_wand/platforms/mac/helper/release\.rb\z},          # macOS helper release script
  %r{\Alib/wifi_wand/platforms/mac/helper/build\.rb\z},            # macOS helper build script
  %r{\Alibexec/macos/(?:src/|wifiwand-helper\.entitlements\z|wifiwand-helper\.source-manifest\.json\z)},
  # ^ macOS helper source code, entitlements, and source manifest
  %r{\Adocs/TESTING\.md\z},                                        # internal testing guide
].freeze

# Resolve the gem's file list from git-tracked files, filtered through the
# whitelist globs and exclusion regexps defined above.  This keeps the list
# in sync with version control and prevents untracked cruft from leaking in.
resolve_files = -> {
  Dir.chdir(File.expand_path(__dir__)) do
    tracked = `git ls-files -z`.split("\x0")
    eligible = tracked.select { |f| packaged_file_patterns.any? { |pat| File.fnmatch?(pat, f, File::FNM_PATHNAME) } }
    eligible.reject { |f| excluded_packaged_files.any? { |pat| pat.match?(f) } }
  end
}

Gem::Specification.new do |spec|
  spec.name          = 'wifi-wand'
  spec.version       = version
  spec.authors       = ['Keith Bennett']
  spec.email         = ['keithrbennett@gmail.com']
  spec.description   = 'A command line interface for managing WiFi on Mac and Ubuntu systems.'
  spec.summary       = 'Cross-platform WiFi management utility'
  spec.homepage      = 'https://github.com/keithrbennett/wifiwand'
  spec.license       = 'Apache-2.0'

  spec.metadata = {
    'source_code_uri'       => 'https://github.com/keithrbennett/wifiwand',
    'bug_tracker_uri'       => 'https://github.com/keithrbennett/wifiwand/issues',
    'changelog_uri'         => 'https://github.com/keithrbennett/wifiwand/blob/main/RELEASE_NOTES.md',
    'rubygems_mfa_required' => 'true',
  }

  spec.files = resolve_files.call
  # Executable scripts live under exe/; derive the bindir and the list of
  # executables from the resolved file list so they stay in sync automatically.
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2.0'

  spec.add_dependency('amazing_print', '~> 2.0')

  # reline will no longer be part of the default gems starting from Ruby 3.5.0.
  spec.add_dependency 'reline', '~> 0.5'
  # still on version 0, no need to exclude future versions, but need bug fix for pry not pry'ing
  # on last line of method:
  spec.add_dependency('pry', '~> 0.14', '>= 0.14.2')

  # Post-install message directing macOS users to the location-permission
  # setup script and quick-start guide.
  spec.post_install_message = <<~MESSAGE

    ╔═══════════════════════════════════════════════════════════════════╗
    ║  ⚠️  Important for macOS Users (10.15+)                           ║
    ╚═══════════════════════════════════════════════════════════════════╝

    wifi-wand requires Ruby >= 3.2.0 and location permission.

    If you are using an older version, such as version 2.6 shipped with
    macOS, the easiest way to install a modern Ruby is with Homebrew:

        brew install ruby

    Then add to your shell profile (~/.zshrc or ~/.bash_profile):

        # Apple Silicon Macs:
        export PATH="/opt/homebrew/opt/ruby/bin:$PATH"

        # Intel Macs:
        export PATH="/usr/local/opt/ruby/bin:$PATH"

    After installing wifi-wand, run the one-time setup script:

        wifiwand-macos-setup

    For more information, see: docs/MACOS_QUICK_START.md
    or visit: https://github.com/keithrbennett/wifiwand/blob/main/docs/MACOS_QUICK_START.md

    MESSAGE
end
