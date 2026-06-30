# -*- encoding: utf-8 -*-
# stub: google_sign_in 1.3.1 ruby lib

Gem::Specification.new do |s|
  s.name = "google_sign_in".freeze
  s.version = "1.3.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["David Heinemeier Hansson".freeze, "George Claghorn".freeze]
  s.date = "1980-01-02"
  s.email = ["david@basecamp.com".freeze, "george@basecamp.com".freeze]
  s.homepage = "https://github.com/basecamp/google_sign_in".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Sign in (or up) with Google for Rails applications".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<rails>.freeze, [">= 6.1.0"])
  s.add_runtime_dependency(%q<google-id-token>.freeze, [">= 1.4.0"])
  s.add_runtime_dependency(%q<oauth2>.freeze, [">= 1.4.0"])
end
