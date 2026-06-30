# -*- encoding: utf-8 -*-
# stub: google-id-token 1.4.2 ruby lib

Gem::Specification.new do |s|
  s.name = "google-id-token".freeze
  s.version = "1.4.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Tim Bray".freeze, "Bob Aman".freeze]
  s.date = "2017-09-11"
  s.description = "Google ID Token utilities; currently just a parser/checker".freeze
  s.email = "tbray@textuality.com".freeze
  s.homepage = "https://github.com/google/google-id-token/".freeze
  s.licenses = ["APACHE-2.0".freeze]
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Google ID Token utilities".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<jwt>.freeze, [">= 1"])
  s.add_development_dependency(%q<fakeweb>.freeze, [">= 0"])
  s.add_development_dependency(%q<rake>.freeze, [">= 0"])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0"])
  s.add_development_dependency(%q<openssl>.freeze, [">= 0"])
end
