# This project is trying to help writing concurrent program with ruby a little easier.     

# select_chan                       
select channels like golang in ruby

Chan is buffered or non-buffered, just like make(chan Type,n) or make(chan Type) in golang
but not statically typed in my implementation.

example:

```ruby
require 'rbgo'

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


timeout_ch = Chan.after(4)
job_ch1 = Chan.perform do
  #do some job
  sleep 
end

job_ch2 = Chan.perform(timeout: 3) do
  #do some job
  sleep
end


select_chan(
  on_read(chan: job_ch1){
    p :job_ch1
  },
  on_read(chan: job_ch2){
    p :job_ch2
  },
  on_read(chan: timeout_ch){
    p 'timeout'
  }
)        
        
# Chan is Enumerable
 
ch = Chan.new

go do
  10.times do
    ch << Time.now
  end
end

ch.each do|obj|
  p obj
end
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

# Actors can be parent-child relationship, and can be linked or monitored
 
supervisor = Rbgo::Actor.new do |msg, actor|
  case msg
  when Rbgo::ActorClosedMsg
    p msg.actor.close_reason # why actor closed
    actor.spawn_monitor(&msg.actor.handler) # spawn again
  end
end

10000.times do
  supervisor.spawn_monitor do |msg, _|  # when these actors closed, supervisor will receive ActorClosedMsg
                                        # and decide what to do
    p msg
  end
end

link1 = Rbgo::Actor.new do |msg, actor|
end
link2 = link1.spawn_link do
end

link1.close # any one of linked actors close will cause all other close

# link / unlink
# monitor / demonitor   
# when use spawn_xx , actors have parent-child relationship 


# TaskList do task in order but do it asynchronously, task may be executed in different thread
 
task_list = Rbgo::TaskList.new

task_1 = proc do
  puts 'first'
  1
end

task_2 = proc do |last_result|
  puts 'second'
  puts "last task result #{last_result}"
  sleep 5
  2
end

task_3 = proc do |last_result|
  puts 'third'
  puts "last task result #{last_result}"
  3
end

task_list << task_1
task_list.add(task_2, timeout: 2, skip_on_exception: true)
task_list << task_3

task_list.start
task_list.wait
p 'wait done.'                          
p task_list.complete?
p task_list.last_error
                       
# Reentrant/ReadWirte Mutex and Semaphore

m = Rbgo::ReentrantMutex.new
m.synchronize do
  m.synchronize do
    puts "I'm here!"
  end
end

m2 = Rbgo::RWMutex.new
5.times do
  go do
    m2.synchronize_r do
      puts "got the read lock"
    end
  end
end
go do
  m2.synchronize_w do
    puts "got the write lock"
    m2.synchronize_r do
      puts 'now, downgrade to read lock'
    end
  end
end

sleep 2

go do
  s = Rbgo::Semaphore.new(5)

  s.acquire(4) do
    puts 'got the permits'
  end

  s.acquire_all do
    puts 'got all available permits'
  end

  ok = s.try_acquire do
    puts 'try success'
  end
  puts 'try ok!' if ok
end
```            
# IOMachine
IOMachine wrap nio4r to do IO operation asynchronously.

support platforms: MRI, JRuby.

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
              
require 'open-uri'
go do
  res = yield_io do
    f = open("http://www.google.com")
    f.read
  end
  p res
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

```


# NetworkService

open TCP or UDP service 

Because service handles network request in async mode, it can handle many requests concurrently. If use some Non-GIL ruby implementations such as TruffleRuby or JRuby, it can utilize all your CPU cores.  

Use IO#yield_read IO#yield_write to do IO operations

```ruby  
require 'rbgo'

using Rbgo::CoRunExtensions

#localhost, port 3000
tcp_service = Rbgo::NetworkServiceFactory.open_tcp_service(3000) do|sock, _|
  sock.yield_read_line("\r\n\r\n") # read http request
  sock.close_read
  sock.yield_write("HTTP/1.1 200 OK \r\n\r\nHello World!")
  sock.close_write
  sock.close
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
