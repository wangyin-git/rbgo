# select_chan
select channels like golang in ruby

Chan is buffered, just like make(chan type,n) in golang

example:

```ruby
require_relative 'select_chan'


ch1 = Chan.new(3)
ch2 = Chan.new(2)
ch3 = Chan.new(1)

ch3 << 'hello'

select_chan(
  on_read(chan: ch1){|obj|
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

example:

```ruby
require_relative 'corun'
require_relative 'wait_group'

using CoRunExtensions

wg = WaitGroup.new

wg.add(1)
go do
  puts 'start'
  Fiber.yield
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

```        
# NonBufferQueue                                
NonBUfferQueue is like non-buffer chan in golang, but it can not be used directly in select_chan, because I dont known how to implement nonblock semantics

example:

```ruby   
require_relative 'corun'
require_relative 'non_buffer_queue'

using CoRunExtensions
  
queue = NonBufferQueue.new
  
go do
  queue << 1
end
  
go do
  queue << 2
end
  
obj1, ok = queue.deq
p [obj1, ok]
  
queue.close
  
obj2, ok = queue.deq
p [obj2, ok]

```    
# NetworkService

open TCP or UDP service 

because service handles network request in async mode, it can handle many requests concurrently. If use some Non-GIL ruby implementations such as Truffleruby or Jruby, it can utilize all your CPU cores.  


```ruby  
require_relative 'network_service'
        
#localhost, port 3000
tcp_service = NetworkServiceFactory.open_tcp_service(3000) do|sock, clientAddrInfo|
  p [sock, clientAddrInfo]
end                  

                                        

p "start tcp service: #{[tcp_service.host, tcp_service.port, tcp_service.type]}"
                            
          

#localhost, port random pick
udp_service = NetworkServiceFactory.open_udp_service(0) do|msg, reply_msg|
  p msg
  reply_msg.reply("I receive your message")
end

p "start udp service: #{[udp_service.host, udp_service.port, udp_service.type]}"
           



sleep

``` 
