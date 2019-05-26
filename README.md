# select_chan
select channels like golang in ruby

example:

```
require_relative 'select_chan'

include Channel

ch1 = Chan.new(3)
ch2 = Chan.new(2)
ch3 = Chan.new(1)

ch3 << 'hello'

select_chan(
  on_read(chan: ch1),
  on_read(chan: ch2),
  on_write(chan: ch3, obj: 'world')
){ puts 'call default block' }
```
