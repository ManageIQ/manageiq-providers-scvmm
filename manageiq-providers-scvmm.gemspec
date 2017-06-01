$:.push File.expand_path("../lib", __FILE__)

require "manageiq/providers/scvmm/version"

Gem::Specification.new do |s|
  s.name        = "manageiq-providers-scvmm"
  s.version     = ManageIQ::Providers::Scvmm::VERSION
  s.authors     = ["ManageIQ Developers"]
  s.homepage    = "https://github.com/ManageIQ/manageiq-providers-scvmm"
  s.summary     = "Scvmm Provider for ManageIQ"
  s.description = "Scvmm Provider for ManageIQ"
  s.licenses    = ["Apache-2.0"]

  s.files = Dir["{app,config,lib}/**/*"]

  s.add_development_dependency "codeclimate-test-reporter", "~> 1.0.0"
  s.add_development_dependency "simplecov"
end
