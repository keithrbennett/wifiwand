# coding: utf-8

require_relative 'lib/wifi-wand/version'

Gem::Specification.new do |spec|
  spec.name          = "wifi-wand"
  spec.version       = WifiWand::VERSION
  spec.authors       = ["Keith Bennett"]
  spec.email         = ["keithrbennett@gmail.com"]
  spec.description   = %q{A command line interface for managing WiFi on a Mac.}
  spec.summary       = %q{Mac WiFi utility}
  spec.homepage      = "https://github.com/keithrbennett/wifiwand"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.require_paths = ["lib"]

  # spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.add_dependency('awesome_print', '~> 1.9')

  # still on version 0, no need to exclude future versions, but need bug fix for pry not pry'ing
  # on last line of method:
  spec.add_dependency('pry', '>= 0.14.2')

  spec.add_dependency('rexml', '~> 3.0')

  spec.add_development_dependency "bundler", ">= 2.2.10"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"

end
