local ffi = require("ffi")

pcall(ffi.cdef, "typedef long int __fd_mask;")
pcall(ffi.cdef, [[
typedef struct {
  __fd_mask __fds_bits[16];
} fd_set;
]])
