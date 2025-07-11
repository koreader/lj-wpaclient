local ffi = require("ffi")

pcall(ffi.cdef, "typedef long int __fd_mask;")
pcall(ffi.cdef, [[
typedef struct {
  __fd_mask __fds_bits[32];
} fd_set;
]])
