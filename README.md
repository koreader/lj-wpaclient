lj-wapclient
============

LuaJIT client for wpa_supplicant control protocol.


Dependencies
------------

 * LuaJIT


Usage
-----
High level API `WpaClient` is defined in `wpaclient.lua`. Following is a quick
example on how it can be used communicate with wpa_supplicant:

```lua
loacl WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')
print( wcli:sendCmd('PING') )
wcli:close()
```

Lower level APIs are defined in `wpa_ctrl.lua`. It mimics the C APIs defined in
`wpa_ctrl.h` from hostap project. See `wpaclient.lua` for example code.
