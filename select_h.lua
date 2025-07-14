local ffi = require("ffi")

pcall(ffi.cdef, "static const int POLLRDNORM = 64;")
pcall(ffi.cdef, "static const int POLLRDBAND = 128;")
