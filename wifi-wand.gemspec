require_relative 'lib/wifi-wand/version'

Gem::Specification.new do |spec|
  spec.name          = "wifi-wand"
  spec.version       = WifiWand::VERSION
  spec.authors       = ["Keith Bennett"]
  spec.email         = ["keithrbennett@gmail.com"]
  spec.description   = %q{A command line interface for managing WiFi on Mac and Ubuntu systems.}
  spec.summary       = %q{Cross-platform WiFi management utility}
  spec.homepage      = "https://github.com/keithrbennett/wifiwand"
  spec.license       = "Apache-2.0"

  spec.metadata = {
    "source_code_uri" => "https://github.com/keithrbennett/wifiwand",
    "bug_tracker_uri" => "https://github.com/keithrbennett/wifiwand/issues",
    "changelog_uri"   => "https://github.com/keithrbennett/wifiwand/blob/main/RELEASE_NOTES.md"
  }

  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      # Exclude developer-only files (code signing docs, release rake tasks)
      f.match(%r{^(lib/tasks/dev|docs/dev)/})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency('awesome_print', '>= 1.9.2', '< 2')

  # ostruct and reline will no longer be part of the default gems starting from Ruby 3.5.0.
  spec.add_dependency 'ostruct', '~> 0.6'
  spec.add_dependency 'reline', '~> 0.5'
  # still on version 0, no need to exclude future versions, but need bug fix for pry not pry'ing
  # on last line of method:
  spec.add_dependency('pry', '~> 0.14', '>= 0.14.2')

  # async provides clean fiber-based concurrency for network connectivity testing
  spec.add_dependency('async', '~> 2.0')

  # Post-install message for macOS users about location permission setup
  spec.post_install_message = if RbConfig::CONFIG['host_os'] =~ /darwin/i
    <<~MESSAGE

      ╔═══════════════════════════════════════════════════════════════════╗
      ║  ⚠️  Important for macOS Users (10.15+)                           ║
      ╚═══════════════════════════════════════════════════════════════════╝

      wifi-wand requires location permission to access WiFi network names.

      Run the one-time setup script:

          wifi-wand-macos-setup

      For more information, see: docs/MACOS_SETUP.md
      or visit: https://github.com/keithrbennett/wifiwand/blob/main/docs/MACOS_SETUP.md

    MESSAGE
  end
end
