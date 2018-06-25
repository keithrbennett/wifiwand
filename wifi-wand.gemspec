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

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"

end

