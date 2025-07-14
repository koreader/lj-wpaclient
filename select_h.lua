local ffi = require("ffi")

pcall(ffi.cdef, "typedef long int __fd_mask;")
pcall(ffi.cdef, [[
typedef struct {
  __fd_mask __fds_bits[32];
} fd_set;
]])
pcall(ffi.cdef, "int select(int, fd_set *restrict, fd_set *restrict, fd_set *restrict, struct timeval *restrict);")

pcall(ffi.cdef, "static const int POLLRDNORM = 64;")
pcall(ffi.cdef, "static const int POLLRDBAND = 128;")
