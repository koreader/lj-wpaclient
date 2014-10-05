local ffi = require("ffi")

ffi.cdef[[
static const int AF_UNIX = 1;
static const int SOCK_DGRAM = 2;
struct sockaddr {
  short unsigned int sa_family;
  char sa_data[14];
};
int socket(int, int, int) __attribute__((__nothrow__, __leaf__));
int bind(int, const struct sockaddr *, unsigned int) __attribute__((__nothrow__, __leaf__));
int connect(int, const struct sockaddr *, unsigned int);
long int recvfrom(int, void *restrict, size_t, int, struct sockaddr *restrict, unsigned int *restrict);
long int send(int, const void *, size_t, int);

int close(int);

static const int POLLIN = 1;
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
int poll(struct pollfd *, long unsigned int, int);
]]

local sockaddr_pt = ffi.typeof('struct sockaddr *')

local Socket = {
    AF_UNIX = ffi.C.AF_UNIX,
    SOCK_DGRAM = ffi.C.SOCK_DGRAM,
    __index = {},
}

function Socket.new(domain, stype, protocol)
    local instance = {
        fd = ffi.C.socket(domain, stype, protocol),
    }
    if instance.fd < 0 then
        return nil
    else
        return setmetatable(instance, Socket)
    end
end

function Socket.__index:connect(saddr, saddr_type)
    return ffi.C.connect(self.fd, ffi.cast(sockaddr_pt, saddr),
                         ffi.sizeof(saddr_type))
end

function Socket.__index:bind(saddr, saddr_type)
    return ffi.C.bind(self.fd, ffi.cast(sockaddr_pt, saddr),
                      ffi.sizeof(saddr_type))
end

function Socket.__index:close()
    return ffi.C.close(self.fd)
end

function Socket.__index:send(buf, len, flags)
    return ffi.C.send(self.fd, buf, len, flags)
end

function Socket.__index:__recvfrom(buf, len, flags)
    --@TODO support for parsing (host, port) tuple 04.10 2014 (houqp)
    local re = ffi.C.recvfrom(self.fd, buf, len, flags, nil, nil)
    if re < 0 then
        return nil, re
    else
        return { buf = ffi.string(buf, re) }, re
    end
end

function Socket.__index:recvfrom(len, flags)
    local buf = ffi.new('char[?]', len)
    local tuple, re = self:__recvfrom(buf, len, flags)
    return tuple, re
end

function Socket.__index:recvfromAll(flags)
    -- FIXME: hard coded buf length stolen from:
    -- wpa_supplicant/ctrl_iface_unix.c
    local buf_len = 4096
    local re = -1
    local tuple
    local buf = ffi.new('char[?]', buf_len)
    local full_buf = ''
    local full_buf_len = 0

    local evs = ffi.new('struct pollfd[1]')
    evs[0].fd = self.fd
    evs[0].events = ffi.C.POLLIN

    while true do
        re = ffi.C.poll(evs, 1, 1)
        if re <= 0 or bit.band(evs[0].revents, ffi.C.POLLIN) == 0 then
            break
        else
            tuple, re = self:__recvfrom(buf, buf_len, flags)
            full_buf_len = full_buf_len + re

            if re <= 0 then break end

            if not full_buf then
                full_buf = tuple.buf
            else
                full_buf = full_buf .. tuple.buf
            end
        end
    end

    return { buf = full_buf }, full_buf_len
end

function Socket.__index:closeOnError(msg)
    ffi.C.close(self.fd)
    return msg
end

return Socket
