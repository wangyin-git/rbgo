# select_chan
select channels like golang in ruby

example:

```
require_relative 'select_chan'


ch1 = Chan.new(3)
ch2 = Chan.new(2)
ch3 = Chan.new(1)

ch3 << 'hello'

select_chan(
  on_read(chan: ch1){
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
