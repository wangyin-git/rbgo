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
  s.description = <<-END
                    You can produce a light weight routine easily with a method 'go' and communicate with each routine by channel.

                    In MRI the GIL prevents you from running code parallelly, but there ara also other ruby implementations such as TruffleRuby or JRuby which can utilize all CPU cores.

                    In MRI write program to run concurrently even not parallelly is also important.
                  END
  s.add_dependency "sys-cpu", "~> 0.8"
  s.files         = `git ls-files`.split("\n")
  s.license       = 'MIT'
end