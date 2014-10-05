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

static const int EPOLLIN = 1;
static const int EPOLL_CTL_ADD = 1;
union epoll_data {
  void *ptr;
  int fd;
  uint32_t u32;
  uint64_t u64;
};
struct epoll_event {
  uint32_t events;
  union epoll_data data;
} __attribute__((__packed__));
int epoll_create(int) __attribute__((__nothrow__, __leaf__));
int epoll_ctl(int, int, int, struct epoll_event *) __attribute__((__nothrow__, __leaf__));
int epoll_wait(int, struct epoll_event *, int, int);
]]

local sockaddr_pt = ffi.typeof('struct sockaddr *')
local epoll_event_t = ffi.typeof('struct epoll_event')

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

function Socket.__index:isReadable()
    --@TODO check epoll_create and epoll_ctl return  05.10 2014 (houqp)
    epollfd = ffi.C.epoll_create(1)
    events = ffi.new(epoll_event_t)
    watch_ev = ffi.new(epoll_event_t)
    watch_ev.events = ffi.C.EPOLLIN
    watch_ev.data.fd = self.fd
    ffi.C.epoll_ctl(epollfd, ffi.C.EPOLL_CTL_ADD, self.fd, watch_ev)
    ffi.C.epoll_wait(epollfd, events, 1, 1)
    if events.data.fd == self.fd then
        return true
    else
        return false
    end
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

    while self:isReadable() do
        tuple, re = self:__recvfrom(buf, buf_len, flags)
        full_buf_len = full_buf_len + re

        if re <= 0 then break end

        if not full_buf then
            full_buf = tuple.buf
        else
            full_buf = full_buf .. tuple.buf
        end
    end

    return { buf = full_buf }, full_buf_len
end

function Socket.__index:closeOnError(msg)
    ffi.C.close(self.fd)
    return msg
end

return Socket
