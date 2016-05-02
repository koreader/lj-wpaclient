lj-wpaclient
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
local WpaClient = require('wpaclient')
local wcli = WpaClient.new('/var/run/wpa_supplicant/wlan0')
wcli:doScan()
print("[*] scan results")
for _, entry in pairs(wcli:getScanResults()) do
    print("bssid:", entry.bssid, "ssid:", (entry.ssid or "[hidden]") .. "  " .. entry.flags)
end
wcli:close()
```

Lower level APIs are defined in `wpa_ctrl.lua` and used in `wpaclient.lua`. It
mimics C APIs defined in `wpa_ctrl.h` from hostap project.
