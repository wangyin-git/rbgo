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




```            
# NetworkService

open TCP or UDP service 

Because service handles network request in async mode, it can handle many requests concurrently. If use some Non-GIL ruby implementations such as TruffleRuby or JRuby, it can utilize all your CPU cores.  


```ruby  
require 'rbgo'

#localhost, port 3000
tcp_service = Rbgo::NetworkServiceFactory.open_tcp_service(3000) do|sock, clientAddrInfo|
  p [sock, clientAddrInfo]
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
