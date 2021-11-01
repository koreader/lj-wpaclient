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
    local lvl, msg = string.match(ev_str, "^<(%d)>(.-)%s*$")
    if not lvl then
        print("wpa_ctrl failed to parse unsolicited message:", ev_str)
        return
    end
    local ev = {lvl = ev_lv2str[lvl], msg = msg}
    setmetatable(ev, event_mt)
    self:push(ev)
end

function event_queue_mt.__index:parse_ifname(ev_str)
    local ev = {lvl = "INFO", msg = ev_str}
    setmetatable(ev, event_mt)
    self:push(ev)
end

function event_queue_mt.__index:push(ele)
    if #self.queue >= MAX_EV_QUEUE_SZ then
        table.remove(self.queue, 1)
    end
    table.insert(self.queue, ele)
end

function event_queue_mt.__index:pop()
    return table.remove(self.queue)
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
        return nil, "Failed to initialize socket instance"
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
    local data, re
    re = hdl.sock:send(cmd, #cmd, 0)
    if re < #cmd then
        return nil, "Failed to send command: " .. cmd
    end
    data, re = hdl.sock:recvAll(0, hdl.event_queue)
    if re <= 0 then
        return nil, "No response from wpa_supplicant"
    end
    return data, re
end

function wpa_ctrl.waitForResponse(hdl, timeout)
    return hdl.sock:canRead(timeout)
end

function wpa_ctrl.readResponse(hdl)
    local data, re = hdl.sock:recvAll(0, hdl.event_queue)
    if re <= 0 then
        return nil, "No response from wpa_supplicant"
    end
    return data, re
end

function wpa_ctrl.command(hdl, cmd, block)
    local reply, err_msg = wpa_ctrl.request(hdl, cmd)
    if block and (reply == nil or #reply == 0) then
        -- Wait at most 10s for a response (e.g., scans can take a significant amount of time)
        if wpa_ctrl.waitForResponse(hdl, 10 * 1000) then
            local re
            reply, re = wpa_ctrl.readResponse(hdl)
            if reply == nil or re < 0 then
                -- i.e., empty reply or read failure
                return nil, "Empty reply"
            end
            err_msg = re
        else
            return nil, "Timed out"
        end
    end
    return reply, err_msg
end

function wpa_ctrl.status_command(hdl, cmd, block)
    local reply, err_msg = wpa_ctrl.request(hdl, cmd)
    if block and (reply == nil or #reply == 0) then
        -- Wait at most 10s for an actual response, not an unsolicited message, hence the #reply check...
        local cnt = 0
        local max_retry = 10
        while (reply == nil or #reply == 0) do
            if wpa_ctrl.waitForResponse(hdl, 1 * 1000) then
                local re
                reply, re = wpa_ctrl.readResponse(hdl)
                if reply == nil or re < 0 then
                    -- i.e., empty reply or read failure
                    return nil, "Empty reply"
                end
                err_msg = re
            else
                -- Timed out
                cnt = cnt + 1
            end

            if cnt > max_retry then
                return nil, "Timed out"
            end
        end
    end
    return reply, err_msg
end

function wpa_ctrl.attach(hdl)
    return wpa_ctrl.status_command(hdl, "ATTACH", true)
end

function wpa_ctrl.reattach(hdl)
    return wpa_ctrl.status_command(hdl, "REATTACH", true)
end

function wpa_ctrl.readEvent(hdl)
    return hdl.event_queue:pop()
end

function wpa_ctrl.detach(hdl)
    return wpa_ctrl.status_command(hdl, "DETACH", true)
end

return wpa_ctrl
