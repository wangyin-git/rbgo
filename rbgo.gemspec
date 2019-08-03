# -*- encoding: utf-8 -*-

require_relative "lib/rbgo/version"

Gem::Specification.new do |s|
  s.name        = "rbgo"
  s.version     = Rbgo::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Wang Yin"]
  s.email       = ["24588062@qq.com"]
  s.homepage    = "https://github.com/wangyin-git/select_chan"
  s.summary     = "Write concurrent program with Ruby in Golang style"
  s.description = "Write concurrent program with Ruby in Golang style"
  s.add_dependency "sys-cpu", "~> 0.8"
  s.files         = `git ls-files`.split("\n")
  s.license       = 'MIT'
end