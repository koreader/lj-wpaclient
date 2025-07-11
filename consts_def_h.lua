local ffi = require("ffi")

pcall(ffi.cdef, "static const int SOCK_DGRAM = 2;")
pcall(ffi.cdef, "static const int SOCK_NONBLOCK = 2048;")
pcall(ffi.cdef, "static const int EISCONN = 106;")
