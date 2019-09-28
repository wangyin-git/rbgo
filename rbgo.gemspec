# -*- encoding: utf-8 -*-

require_relative "lib/rbgo/version"

Gem::Specification.new do |s|
  s.name        = "rbgo"
  s.version     = Rbgo::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Wang Yin"]
  s.email       = ["24588062@qq.com"]
  s.homepage    = "https://github.com/wangyin-git/rbgo"
  s.summary     = "Write concurrent program with Ruby in Golang style"
  s.description = "Write concurrent program with Ruby in Golang style."
  s.add_dependency "system", "~> 0.1.3"
  s.add_dependency "nio4r", "~> 2.4"
  s.add_dependency "einhorn", "~> 0.7"
  s.files         = `git ls-files`.split("\n")
  s.license       = 'MIT'
end