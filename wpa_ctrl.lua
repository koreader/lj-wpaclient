local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require("ffi")
local C = ffi.C
local Socket = require(cur_path .. "socket")

ffi.cdef[[
unsigned int sleep(unsigned int seconds);
struct sockaddr_un {
  short unsigned int sun_family;
  char sun_path[108];
};
int unlink(const char *) __attribute__((nothrow, leaf));
]]


local sockaddr_un_t = ffi.typeof("struct sockaddr_un")

local event_mt = {__index = {}}

local wpa_ctrl = {}

function event_mt.__index:isAuthSuccessful()
    return (string.find(self.msg, "^CTRL%-EVENT%-CONNECTED")
            or string.match(self.msg, "^%w+: Key negotiation completed with (.+)$") ~= nil)
end

function event_mt.__index:isScanEvent()
    return (self.msg == "WPS-AP-AVAILABLE"
            or self.msg == "CTRL-EVENT-SCAN-RESULTS"
            or string.match(self.msg, "^CTRL%-EVENT%-BSS%-%w+ %d+ .*$") ~= nil)
end

function event_mt.__index:isAuthFailed()
    return (string.find(self.msg, "^CTRL%-EVENT%-DISCONNECTED")
            or string.match(self.msg, "^Authentication with (.-) timed out$") ~= nil)
end

local ev_lv2str = {
    ["0"] = "MSGDUMP",
    ["1"] = "DEBUG",
    ["2"] = "INFO",
    ["3"] = "WARNING",
    ["4"] = "ERROR",
}
local MAX_EV_QUEUE_SZ = 1024
local event_queue_mt = {__index = {}}

function event_queue_mt.__index:parse(ev_str)
    print("event_queue_mt.__index:parse", ev_str)
    local lvl, msg = string.match(ev_str, "^<(%d)>(.-)%s*$")
    if not lvl then
        print("failed to parse")
        -- TODO: log error
        return
    end
    local ev = {lvl = ev_lv2str[lvl], msg = msg}
    setmetatable(ev, event_mt)
    print("ev:", ev.lvl, ev.msg)
    self:push(ev)
end

function event_queue_mt.__index:parse_ifname(ev_str)
    print("event_queue_mt.__index:parse_ifname", ev_str)
    local ev = {lvl = "INFO", msg = ev_str}
    setmetatable(ev, event_mt)
    print("ev:", ev.lvl, ev.msg)
    self:push(ev)
end

function event_queue_mt.__index:push(ele)
    print("event_queue_mt.__index:push", ele.msg)
    if #self.queue >= MAX_EV_QUEUE_SZ then
        print("overflow, dropped oldest")
        table.remove(self.queue, 1)
    end
    table.insert(self.queue, ele)
end

function event_queue_mt.__index:pop()
    local ele = table.remove(self.queue)
    print("event_queue_mt.__index:pop", ele and ele.msg or "nil")
    return ele
end

local function new_event_queue()
    local q = {queue = {}}
    setmetatable(q, event_queue_mt)
    return q
end

function wpa_ctrl.open(ctrl_sock)
    local re
    local hdl = {
        sock = nil,
        recv_sock_path = nil,
        local_saddr = sockaddr_un_t(Socket.AF_UNIX),
        dest_saddr = sockaddr_un_t(Socket.AF_UNIX),
        event_queue = nil,
    }

    -- Clean up potentially stale socket
    hdl.recv_sock_path = "/tmp/lj-wpaclient-" .. tostring(C.getpid())
    C.unlink(hdl.recv_sock_path)
    ffi.copy(hdl.local_saddr.sun_path, hdl.recv_sock_path)
    ffi.copy(hdl.dest_saddr.sun_path, ctrl_sock)

    hdl.sock = Socket.new(Socket.AF_UNIX, Socket.SOCK_DGRAM, 0)
    if not hdl.sock then
        return nil, "Failed to initilize socket instance"
    end
    re = hdl.sock:bind(hdl.local_saddr, sockaddr_un_t)
    if re < 0 then
        return nil, hdl.sock:closeOnError("Failed to bind socket: " .. hdl.recv_sock_path)
    end
    re = hdl.sock:connect(hdl.dest_saddr, sockaddr_un_t)
    if re < 0 then
        return nil, hdl.sock:closeOnError("Failed to connect to wpa_supplicant control socket: " .. ctrl_sock)
    end

    hdl.event_queue = new_event_queue()
    return hdl
end

function wpa_ctrl.close(hdl)
    if hdl.recv_sock_path then
        C.unlink(hdl.recv_sock_path)
    end
    if hdl.sock then
        hdl.sock:close()
    end
end

function wpa_ctrl.request(hdl, cmd)
    print("wpa_ctrl.request", cmd)
    local data, re
    re = hdl.sock:send(cmd, #cmd, 0)
    if re < #cmd then
        return nil, "Failed to send command: " .. cmd
    end
    data, re = hdl.sock:recvAll(0, hdl.event_queue)
    if re < 0 then
        return nil, "No response from wpa_supplicant"
    end
    return data
end

function wpa_ctrl.readResponse(hdl)
    print("wpa_ctrl.readResponse")
    local data, re = hdl.sock:recvAll(0, hdl.event_queue)
    return data, re
end

function wpa_ctrl.command(hdl, cmd)
    local data, re = wpa_ctrl.request(hdl, cmd)
    return data, re
end

function wpa_ctrl.attach(hdl)
    local data, re = wpa_ctrl.request(hdl, "ATTACH")
    return data, re
end

function wpa_ctrl.reattach(hdl)
    local data, re = wpa_ctrl.request(hdl, "REATTACH")
    return data, re
end

function wpa_ctrl.readEvent(hdl)
    print("readEvent")
    return hdl.event_queue:pop()
end

function wpa_ctrl.detach(hdl)
    local data, re = wpa_ctrl.request(hdl, "DETACH")
    return data, re
end


return wpa_ctrl
