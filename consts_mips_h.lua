local ffi = require("ffi")

pcall(ffi.cdef, "static const int SOCK_DGRAM = 1;")
pcall(ffi.cdef, "static const int SOCK_NONBLOCK = 128;")
pcall(ffi.cdef, "static const int EISCONN = 133;")
