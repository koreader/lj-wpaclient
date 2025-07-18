lj-wpaclient
============

Native Lua implementation of client for wpa_supplicant control protocol,
(c.f., https://w1.fi/cgit/hostap/tree/src/common/wpa_ctrl.c).


Dependencies
------------

 * LuaJIT


Usage
-----
High level APIs are defined in `wpaclient.lua`. A quick example on how it can
be used to communicate with wpa_supplicant server:

```lua
local WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')
for _, entry in pairs(wcli:scanThenGetResults()) do
    print("quality:", entry:getSignalQuality(),
          "bssid:", entry.bssid,
          "ssid:", (entry.ssid or "[hidden]"),
          "flags:", entry.flags)
end
wcli:close()
```

Lower level APIs are defined in `wpa_ctrl.lua` and used in `wpaclient.lua`. It
mimics C APIs defined in `wpa_ctrl.h` from hostap project.


### Listen for events

```lua
local WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')
wcli:attach()
wcli:doScan()
while true do
    local incoming = pcall(function() wcli:waitForEvent(-1) end) -- inf wait
    if not incoming then
        break
    end
    local ev = wcli:readEvent()
    if ev ~= nil then
        print('got event:', ev.lvl, ev.msg)
    end
end
wcli:close()
```


### Add and connect to network

```lua
local WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')

local nw_id, err = wcli:addNetwork()
print('[*] got network id: ', nw_id)
wcli:setNetwork(nw_id, "ssid", "\"random-super-safe-free-wifi\"")
wcli:setNetwork(nw_id, "psk", "\"PASSWORD\"")
-- That's it! Now run your favorite DHCP client to obtain an IP :)
wcli:close()
```
