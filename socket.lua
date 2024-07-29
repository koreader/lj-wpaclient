local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require("ffi")
local C = ffi.C
-- We may already have some of these thanks to koreader-base ffi modules,
-- so we load each symbol one-by-one in a protected call...
require(cur_path .. "consts_h")
require(cur_path .. "socket_h")
require(cur_path .. "poll_h")
require(cur_path .. "select_h")


local sockaddr_pt = ffi.typeof("struct sockaddr *")

-- Most of this select tooling is handled via macros in C...
--[[
local __NFDBITS = 8 * ffi.sizeof("__fd_mask")
local function __FD_ELT(d)
    return math.floor(d / __NFDBITS)
end
local function __FD_MASK(d)
    return ffi.cast("__fd_mask", bit.lshift(1, d % __NFDBITS))
end

local function FD_ZERO(s)
    for i = 0, ffi.sizeof("fd_set") / ffi.sizeof("__fd_mask") do
        s.__fds_bits[i] = 0
    end
end

local function FD_SET(d, s)
    local fd_idx = __FD_ELT(d)
    s.__fds_bits[fd_idx] = bit.bor(s.__fds_bits[fd_idx], __FD_MASK(d))
end

local function FD_CLR(d, s)
    local fd_idx = __FD_ELT(d)
    s.__fds_bits[fd_idx] = bit.band(s.__fds_bits[fd_idx], bit.bnot(__FD_MASK(d)))
end

local function FD_ISSET(d, s)
    local fd_idx = __FD_ELT(d)
    return bit.band(s.__fds_bits[fd_idx], __FD_MASK(d)) ~= 0
end
--]]

-- To match FD_ISSET behavior with poll
local POLLIN_SET = bit.bor(C.POLLRDNORM, C.POLLRDBAND, C.POLLIN, C.POLLHUP, C.POLLERR)

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
    local pos = 0
    while len > pos do
        -- NOTE: buf is a Lua string, so this isn't as nice as with real pointer arithmetic...
        local nw = C.send(self.fd, pos == 0 and buf or buf:sub(1 + pos), len - pos, bit.bor(flags, C.MSG_NOSIGNAL))
        if nw == -1 then
            local errno = ffi.errno()
            if errno ~= C.EINTR then
                if errno == C.EAGAIN then
                    local pfd = ffi.new("struct pollfd")
                    pfd.fd = self.fd
                    pfd.events = C.POLLOUT

                    C.poll(pfd, 1, -1)
                    -- Back to send
                else
                    -- Actual error :(
                    return -1
                end
            end
            -- EINTR: Back to send
        else
            pos = pos + nw
        end
    end
    return pos
end

function Socket.__index:recv(buf, len, flags)
    local re = C.recv(self.fd, buf, len, flags)
    if re < 0 then
        return nil, re
    else
        return ffi.string(buf, re), re
    end
end

function Socket.__index:canRead(timeout)
    local pfd = ffi.new("struct pollfd")
    pfd.fd = self.fd
    pfd.events = C.POLLIN

    local re = C.poll(pfd, 1, timeout or 0)
    if re > 0 and bit.band(pfd.revents, POLLIN_SET) ~= 0 then
        -- We've got something to read!
        return true
    end

    return false
end

function Socket.__index:recvAll(flags, event_queue)
    -- NOTE: Length stolen from https://w1.fi/cgit/hostap/tree/wpa_supplicant/ctrl_iface.h#n15
    local buf_len = 8192 + 1
    local buf = ffi.new("unsigned char[?]", buf_len)
    local full_buf = {}
    local full_buf_len = 0

    local pfd = ffi.new("struct pollfd")
    pfd.fd = self.fd
    pfd.events = C.POLLIN

    while true do
        -- No timeout, we handle retries at a higher level, where appropriate
        -- (e.g., WpaClient:scanThenGetResults & WpaClient:sendCmd).
        local re = C.poll(pfd, 1, 0)
        if re == -1 then
            local errno = ffi.errno()
            if errno ~= C.EINTR then
                return nil, re
            end
            -- EINTR: Back to poll
        elseif re > 0 then
            if bit.band(pfd.revents, POLLIN_SET) ~= 0 then
                local data
                data, re = self:recv(buf, buf_len, flags)
                if re < 0 then
                    local errno = ffi.errno()
                    if errno ~= C.EINTR and errno ~= C.EAGAIN then
                        return nil, re
                    end
                    -- EINTR or EAGAIN: Back to poll
                else
                    full_buf_len = full_buf_len + re

                    if data:sub(1, 1) == "<" then
                        -- Record unsolicited messages in event_queue for later use
                        event_queue:parse(data)
                    elseif data:sub(1, 7) == "IFNAME=" then
                        -- Ditto
                        event_queue:parse_ifname(data)
                    else
                        table.insert(full_buf, data)

                        -- Break on control command replies
                        if re > 0 then
                            if data == "OK\n"
                            or data:sub(1, 4) == "FAIL" then
                                -- We're done
                                break
                            end
                        end
                    end
                end
            end
        elseif re == 0 then
            -- Timeout or nothing to read
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
