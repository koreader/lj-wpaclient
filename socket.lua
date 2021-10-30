local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require("ffi")
local C = ffi.C
-- We may already have some of these thanks to koreader-base ffi modules, hence the conditional loading
if pcall(function() return C.AF_UNIX end) == false then
    require(cur_path .. "consts_h")
end
if pcall(function() return C.socket end) == false then
    require(cur_path .. "socket_h")
end
if pcall(function() return C.poll end) == false then
    require(cur_path .. "poll_h")
end
if pcall(function() return C.select end) == false then
    require(cur_path .. "select_h")
end


local sockaddr_pt = ffi.typeof("struct sockaddr *")

local Socket = {
    AF_UNIX = C.AF_UNIX,
    SOCK_DGRAM = C.SOCK_DGRAM,
    __index = {},
}

function Socket.new(domain, stype, protocol)
    local instance = {
        fd = C.socket(domain, bit.bor(stype, C.SOCK_NONBLOCK, C.SOCK_CLOEXEC), protocol),
    }
    if instance.fd < 0 then
        return nil
    else
        return setmetatable(instance, Socket)
    end
end

function Socket.__index:connect(saddr, saddr_type)
    while true do
        local re = C.connect(self.fd, ffi.cast(sockaddr_pt, saddr), ffi.sizeof(saddr_type))
        if re == 0 then
            return 0
        elseif re == -1 then
            if re == C.EISCONN then
                -- Already connected (connect() race)
                return 0
            elseif re ~= C.EINTR then
                -- Actual error, otherwise, retry on EINTR
                return re
            end
        end
    end
end

function Socket.__index:bind(saddr, saddr_type)
    return C.bind(self.fd, ffi.cast(sockaddr_pt, saddr), ffi.sizeof(saddr_type))
end

function Socket.__index:close()
    return C.close(self.fd)
end

function Socket.__index:send(buf, len, flags)
    return C.send(self.fd, buf, len, flags)
end

function Socket.__index:recv(buf, len, flags)
    --- @TODO support for parsing (host, port) tuple 04.10 2014 (houqp)
    local re = C.recv(self.fd, buf, len, flags)
    if re < 0 then
        return nil, re
    else
        return ffi.string(buf, re), re
    end
end

function Socket.__index:recvAll(flags, event_queue)
    -- NOTE: Length stolen from https://w1.fi/cgit/hostap/tree/wpa_supplicant/ctrl_iface.h#n15
    local buf_len = 8192 + 1
    local buf = ffi.new("unsigned char[?]", buf_len)
    local full_buf = {}
    local full_buf_len = 0

    local evs = ffi.new("struct pollfd[1]")
    evs[0].fd = self.fd
    evs[0].events = C.POLLIN

    while true do
        local re = C.poll(evs, 1, 10 * 1000)
        if re == -1 then
            local errno = ffi.errno()
            if errno ~= C.EINTR then
                return nil, re
            end
        elseif re > 0 then
            if bit.band(evs[0].revents, C.POLLIN_SET) ~= 0 then
                local data
                data, re = self:recv(buf, buf_len, flags)
                full_buf_len = full_buf_len + re

                if re < 0 then return nil, re end

                print("Socket.__index:recvAll:", re, data)

                if string.sub(data, 1, 1) == "<"
                   or string.sub(data, 1, 7) == "IFNAME=" then
                    -- Record unsolicited messages in event_queue for later use
                    event_queue:parse(data)
                else
                    table.insert(full_buf, data)
                end
            end
        elseif re == 0 then
            -- Timeout
            break
        end
    end

    return table.concat(full_buf), full_buf_len
end

function Socket.__index:closeOnError(msg)
    C.close(self.fd)
    return msg
end

return Socket
