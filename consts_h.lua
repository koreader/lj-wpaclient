local ffi = require("ffi")

pcall(ffi.cdef, "static const int AF_UNIX = 1;")
pcall(ffi.cdef, "static const int SOCK_DGRAM = 2;")
pcall(ffi.cdef, "static const int SOCK_NONBLOCK = 2048;")
pcall(ffi.cdef, "static const int SOCK_CLOEXEC = 524288;")
pcall(ffi.cdef, "static const int MSG_PEEK = 2;")
pcall(ffi.cdef, "static const int MSG_NOSIGNAL = 16384;")
pcall(ffi.cdef, "static const int EISCONN = 106;")
