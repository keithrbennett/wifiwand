# coding: utf-8
# When changing the version, also change the version and the help text in the README.
VERSION = '1.1.0'

Gem::Specification.new do |spec|
  spec.name          = "mac-wifi"
  spec.version       = VERSION
  spec.authors       = ["Keith Bennett"]
  spec.email         = ["keithrbennett@gmail.com"]
  spec.description   = %q{A command line interface for managing wifi on a Mac.}
  spec.summary       = %q{Mac wifi utility}
  spec.homepage      = "https://github.com/keithrbennett/mac-wifi"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  # spec.add_development_dependency "bundler", "~> 1.3"
  # spec.add_development_dependency "rake", '~> 10.1'
  # spec.add_development_dependency "rspec", '~> 3.0'

end

