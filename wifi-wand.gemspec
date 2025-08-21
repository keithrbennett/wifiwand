# coding: utf-8

require_relative 'lib/wifi-wand/version'

Gem::Specification.new do |spec|
  spec.name          = "wifi-wand"
  spec.version       = WifiWand::VERSION
  spec.authors       = ["Keith Bennett"]
  spec.email         = ["keithrbennett@gmail.com"]
  spec.description   = %q{A command line interface for managing WiFi on Mac and Ubuntu systems.}
  spec.summary       = %q{Cross-platform WiFi management utility}
  spec.homepage      = "https://github.com/keithrbennett/wifiwand"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_dependency('awesome_print', '>= 1.9.2', '< 2')

  # ostruct and reline will no longer be part of the default gems starting from Ruby 3.5.0.
  spec.add_dependency 'ostruct'
  spec.add_dependency 'reline'
  # still on version 0, no need to exclude future versions, but need bug fix for pry not pry'ing
  # on last line of method:
  spec.add_dependency('pry', '>= 0.14.2')

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"

end
