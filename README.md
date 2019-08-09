# I like the way how golang does in concurrency.
 
You can produce a light weight routine easily with a keyword 'go' and communicate with each routine by channel.

In MRI the GIL prevents you from running code parallelly, but there ara also other ruby implementations such as TruffleRuby or JRuby which can utilize all CPU cores.

In MRI write program to run concurrently even not parallelly is also important.

# This project is trying to help writing concurrent program with ruby a little easier.     

# select_chan                       
select channels like golang in ruby

Chan is buffered or non-buffered, just like make(chan Type,n) or make(chan Type) in golang
but not statically typed in my implementation.

example:

```ruby
relative 'rbgo'

include Rbgo::Channel

ch1 = Chan.new  # non-buffer channel
ch2 = Chan.new(2) # buffer channel 
ch3 = Chan.new(1)

ch3 << 'hello'

select_chan(
  on_read(chan: ch1){|obj, ok| # obj is the value read from ch1, ok indicates success or failure by close
    #do when read success
  },
  on_read(chan: ch2){
    #do when read success
  },
  on_write(chan: ch3, obj: 'world'){
    #do when write success
  }
){ puts 'call default block' }
```
# go                                
create lightweight routine like golang

Routine does not create a thread instead it is picked by a thread in pool.

Routine use fiber to yield processor, so you can call Fiber.yield, just like Gosched() in golang.

If routine raise exception it does not affect other routine. Check Routine#alive? to see if it is alive, and check Routine#error to see if something went wrong. 

If routine is suspended by a blocking operation for enough long time, a new thread will be created to handle other routine. Suspended thread will exit when it completes current routine.  

 

example:

```ruby
require 'rbgo'

using Rbgo::CoRunExtensions

wg = Rbgo::WaitGroup.new

wg.add(1)
go do
  puts 'start' 

  Fiber.yield  # like Gosched()

  puts 'end'

  wg.done
end

wg.add(1)
go do
  sleep 1
  puts 'sleep end'
  wg.done
end

wg.wait
puts 'wg.wait done'
                             

# the job that takes very long time or never returns such as 'loop'.
# use Fiber.yield to let other yield jobs on the same thread to run.

go do           
  loop do
    # do some job
    # ...
    Fiber.yield 
  end
end

# Or use go!        

go! do         

# go! force a new thread be created to handle this block, and exit when finish.
# use go! to do blocking operations

end

# Once do block only once

once = Rbgo::Once.new
2.times do
  go do
    once.do { puts 'only once' }
  end
end



# Actor handle message sequentially
  
actor = Rbgo::Actor.new do|msg, actor|     
          case msg
          when :msg1
            # do some work 
          when :msg2
            # do some work
          when :msg3
            actor.send_msg :msg1 
          end
        end

actor.send_msg :msg1 #won't block

```            
# IOMachine
IOMachine wrap nio4r to do IO operation asynchronously.

support platforms: MRI, JRuby.

*Not supported platform: Truffleruby*


```ruby  
require 'rbgo'

io_r, io_w = IO.pipe
machine = Rbgo::IOMachine.new

receipt1 = machine.do_read(io_r, length: 100) # when length > 0, result nil if have not read anything yet when read complete.
receipt2 = machine.do_read(io_r, length: 100) # when length >0, result data bytes length up to 100 if have read some when read complete.
receipt3 = machine.do_read(io_r, length: 0) # when length == 0, result ""
receipt4 = machine.do_read(io_r, length: nil) # when length == nil, read until EOF. return "" if have not read anything.

io_w.write("a"*100)
io_w.write("b"*100)
io_w.write("c"*100)
io_w.close # cause EOF

# if the same io object, and the same read/write operation, operations will complete in sequence.
# so receipt1 complete first, and the receipt2 ...
# if the same io object, but not the same read/write operation,
# or not the same io object, operations will complete in arbitrary order.
receipt1.wait
p receipt1.res # aaa...
receipt2.wait
p receipt2.res # bbb...
receipt3.wait
p receipt3.res # ""
receipt4.wait
p receipt4.res # ccc...

io_r, io_w = IO.pipe
receipt1 = machine.do_write(io_w, str: "hello world!")

receipt1.wait
p receipt1.res # number of bytes written, may be less than str.bytesize if exception raised

```          

# yield_read / yield_write
use IOMachine to do IO operation asynchronously, but write code in a sequential way. 

No callback and another callback...
```ruby                   
require 'rbgo'
using Rbgo::CoRunExtensions

io_r, io_w = IO.pipe
go do
  data = io_r.yield_read(100) # have blocking semantics, but execute asynchronously
                              # this operation will *NOT* block the current thread
                              # when io operation complete, thread will resume to execute from this point.
  p data
end

sleep 2

io_w.write("haha I'm crazy.")
io_w.close

# NOTICE yield_read / yield_write will do yield only in CoRun::Routine.new(*args, new_thread: false, &blk) block
# in other place yield_read / yield_write will do normal IO#read / IO#write
# for example: 
# go do
#   io_r.yield_read # will do yield
# end
# 
# go do
#   fiber = Fiber.new do
#     io_r.yield_read # will not do yield. just do normal IO#read
#   end
#   fiber.resume
# end
# 
# go! do
#   io_r.yield_read # will not do yield. just do normal IO#read
# end

```


# NetworkService

open TCP or UDP service 

Because service handles network request in async mode, it can handle many requests concurrently. If use some Non-GIL ruby implementations such as TruffleRuby or JRuby, it can utilize all your CPU cores.  

Use IO#yield_read IO#yield_write to do IO operations

```ruby  
require 'rbgo'

using Rbgo::CoRunExtensions

#localhost, port 3000
tcp_service = Rbgo::NetworkServiceFactory.open_tcp_service(3000) do|sock, clientAddrInfo|
  p [sock, clientAddrInfo] 
  p sock.yield_read
  sock.yield_write("hello")
  sock.close  #SHOULD CLOSE SOCK MANUALLY since version 0.2.0
end                  

                                        

p "start tcp service: #{[tcp_service.host, tcp_service.port, tcp_service.type]}"           
sleep 5
tcp_service.stop
                            
          

#localhost, port auto pick
udp_service = Rbgo::NetworkServiceFactory.open_udp_service(0) do|msg, reply_msg|
  p msg
  reply_msg.reply("I receive your message")
end

p "start udp service: #{[udp_service.host, udp_service.port, udp_service.type]}"      
sleep 5
udp_service.stop


sleep

``` 
