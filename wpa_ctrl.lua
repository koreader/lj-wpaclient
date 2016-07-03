local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require('ffi')
local Socket = require(cur_path..'socket')

local wpa_ctrl = {}

ffi.cdef[[
unsigned int sleep(unsigned int seconds);
struct sockaddr_un {
  short unsigned int sun_family;
  char sun_path[108];
};
int unlink(const char *) __attribute__((__nothrow__, __leaf__));
]]
local sockaddr_un_t = ffi.typeof('struct sockaddr_un')

math.randomseed(os.time())


local event_mt = {__index = {}}

function event_mt.__index:isAuthSuccessful()
    return string.match(self.msg, '%w+: Key negotiation completed with (.+)') ~= nil
end

function event_mt.__index:isScanEvent()
    return (self.msg == 'WPS-AP-AVAILABLE'
            or self.msg == 'CTRL-EVENT-SCAN-RESULTS'
            or string.match(self.msg, 'CTRL%-EVENT%-BSS%-%w+ %d+ .*') ~= nil)
end

function event_mt.__index:isAuthFailed()
    return (string.match(self.msg, 'Authentication with (.-) timed out') ~= nil
            or self.msg == 'CTRL-EVENT-DISCONNECTED - Disconnect event - remove keys')
end

local ev_lv2str = {
    ['0'] = 'MSGDUMP',
    ['1'] = 'DEBUG',
    ['2'] = 'INFO',
    ['3'] = 'WARNING',
    ['4'] = 'ERROR',
}
local MAX_EV_QUEUE_SZ = 5000
local event_queue_mt = {__index = {}}

function event_queue_mt.__index:parse(ev_str)
    local lvl, msg = string.match(ev_str, '^<(%d)>(.-)%s*$')
    if not lvl then
        -- TODO: log error
        return
    end
    local ev = {lvl = ev_lv2str[lvl], msg = msg}
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


local function file_exists(fn)
    local f = io.open(fn, 'r')
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
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

    -- we only try ten times before give up
    for _=1, 10 do
        hdl.recv_sock_path = '/tmp/lj-wpaclient-'..math.random(0, 100000)
        if not file_exists(hdl.recv_sock_path) then
            break
        else
            hdl.recv_sock_path = nil
        end
    end
    if not hdl.recv_sock_path then
        return nil, "Failed to create temporary unix socket file"
    end
    ffi.copy(hdl.local_saddr.sun_path, hdl.recv_sock_path)
    ffi.copy(hdl.dest_saddr.sun_path, ctrl_sock)

    hdl.sock = Socket.new(Socket.AF_UNIX, Socket.SOCK_DGRAM, 0)
    if not hdl.sock then
        return nil, "Failed to initilize socket instance"
    end
    re = hdl.sock:bind(hdl.local_saddr, sockaddr_un_t)
    if re < 0 then
        return nil, hdl.sock:closeOnError(
            'Failed to bind socket: '..hdl.recv_sock_path)
    end
    re = hdl.sock:connect(hdl.dest_saddr, sockaddr_un_t)
    if re < 0 then
        return nil, hdl.sock:closeOnError(
            'Failed to connect to wpa_supplicant control socket: '..ctrl_sock)
    end

    hdl.event_queue = new_event_queue()
    return hdl
end

function wpa_ctrl.close(hdl)
    if hdl.recv_sock_path then
        ffi.C.unlink(hdl.recv_sock_path)
    end
    if hdl.sock then
        hdl.sock:close()
    end
end

function wpa_ctrl.request(hdl, cmd)
    local re, data
    re = hdl.sock:send(cmd, #cmd, 0)
    if re < #cmd then
        return nil, 'Failed to send command: '..cmd
    end
    -- TODO: pass proper flags to recvfromAll
    data, re = hdl.sock:recvfromAll(0, hdl.event_queue)
    if re < 0 then
        return nil, 'No response from wpa_supplicant'
    end
    return data.buf
end

function wpa_ctrl.readResponse(hdl)
    local data, re = hdl.sock:recvfromAll(0, hdl.event_queue)
    return data.buf, re
end

function wpa_ctrl.command(hdl, cmd)
    local buf, re = wpa_ctrl.request(hdl, cmd)
    return buf, re
end

function wpa_ctrl.attach(hdl)
    wpa_ctrl.request(hdl, 'ATTACH')
end

function wpa_ctrl.readEvent(hdl)
    return hdl.event_queue:pop()
end

function wpa_ctrl.detach(hdl)
    wpa_ctrl.request(hdl, 'DETACH')
end


return wpa_ctrl
