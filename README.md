lj-wapclient
============

Native Lua implementation of client for wpa_supplicant control protocol.


Dependencies
------------

 * LuaJIT


Usage
-----
High level API `WpaClient` is defined in `wpaclient.lua`. Following is a quick
example on how it can be used to communicate with wpa_supplicant server:

```lua
loacl WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')
print( wcli:sendCmd('LIST_NETWORKS') )
wcli:close()
```

Lower level APIs are defined in `wpa_ctrl.lua` and used in `wpaclient.lua`. It
mimics C APIs defined in `wpa_ctrl.h` from hostap project.
