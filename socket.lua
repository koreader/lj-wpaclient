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
            if re == C.EISCONN
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

function Socket.__index:__recvfrom(buf, len, flags)
    --- @TODO support for parsing (host, port) tuple 04.10 2014 (houqp)
    local re = C.recvfrom(self.fd, buf, len, flags, nil, nil)
    if re < 0 then
        return nil, re
    else
        return {buf = ffi.string(buf, re)}, re
    end
end

function Socket.__index:recvfrom(len, flags)
    -- TODO: reuse buffer here to reduce GC pressure
    local buf = ffi.new('char[?]', len)
    local tuple, re = self:__recvfrom(buf, len, flags)
    return tuple, re
end

function Socket.__index:recvfromAll(flags, event_queue)
    -- FIXME: hard coded buf length stolen from:
    -- wpa_supplicant/ctrl_iface_unix.c
    local buf_len = 8192 + 1
    local buf = ffi.new('char[?]', buf_len)
    local full_buf = ''
    local full_buf_len = 0

    local evs = ffi.new('struct pollfd[1]')
    evs[0].fd = self.fd
    evs[0].events = C.POLLIN

    while true do
        --- @todo: Switch to non-blocking?
        local re = C.poll(evs, 1, 1)
        if re == -1 then
            local errno = ffi.errno()
            if errno ~= C.EINTR then
                break
            end
        elseif re > 0 then
            if bit.band(evs[0].revents, C.POLLIN) ~= 0 then
                local tuple
                tuple, re = self:__recvfrom(buf, buf_len, flags)
                full_buf_len = full_buf_len + re

                if re < 0 then return nil, re end

                if string.sub(tuple.buf, 1, 1) == '<' then
                    -- record unsolicited messages in event_queue for later use
                    event_queue:parse(tuple.buf)
                else
                    --- @todo: Switch to table.insert + table.concat
                    if not full_buf then
                        full_buf = tuple.buf
                    else
                        full_buf = full_buf .. tuple.buf
                    end
                end
            end
        elseif re == 0 then
            break
        end
    end

    --- @todo: Hash is useless?
    return { buf = full_buf }, full_buf_len
end

function Socket.__index:closeOnError(msg)
    C.close(self.fd)
    return msg
end

return Socket
