# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'grassgis/version'

Gem::Specification.new do |spec|
  spec.name          = "grassgis"
  spec.version       = GrassGis::VERSION
  spec.authors       = ["Javier Goizueta"]
  spec.email         = ["jgoizueta@gmail.com"]
  spec.summary       = %q{Support for scripting GRASS GIS in Ruby}
  spec.description   = %q{Support for scripting GRASS GIS in Ruby.}
  spec.homepage      = "https://github.com/jgoizueta/grassgis"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "sys_cmd", "~> 1.1"

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", "~> 5.4"

  spec.required_ruby_version = '>= 1.9.3'
end
