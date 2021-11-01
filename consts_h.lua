local ffi = require("ffi")

ffi.cdef[[
static const int AF_UNIX = 1;
static const int SOCK_DGRAM = 2;
static const int SOCK_NONBLOCK = 2048;
static const int SOCK_CLOEXEC = 524288;
static const int MSG_PEEK = 2;
static const int MSG_NOSIGNAL = 16384;
static const int EISCONN = 106;
]]
