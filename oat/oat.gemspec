# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'oat/version'

Gem::Specification.new do |gem|
  gem.name          = "oat"
  gem.version       = Oat::VERSION
  gem.authors       = ["david karapetyan"]
  gem.email         = ["dkarapetyan@gmail.com"]
  gem.description   = %q{Toolkit for talking to OpenStack for provisioning.}
  gem.summary       = %q{Simple DSL for declaratively describing and managing infrastructure.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency "openstack"
  gem.add_runtime_dependency "net-ssh"
end
