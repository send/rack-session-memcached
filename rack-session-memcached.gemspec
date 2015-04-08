# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "rack-session-memcached"
  spec.version       = "0.1.0"
  spec.authors       = ["SAKAI, Kazuaki"]
  spec.email         = ["kaz.july.7@gmail.com"]

  spec.summary       = %q{Rack::Session::Memcached provides cookie based session stored in memcached.}
  spec.description   = %q{Rack::Session::Memcached provides cookie based session stored in memcached. It depends on memcached(libmemcached).}
  spec.homepage      = "https://github.com/send/rack-session-memcached"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.8"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rack-test"
  spec.add_dependency "memcached"
  spec.add_dependency "rack"
end
