local ffi = require("ffi")

pcall(ffi.cdef, "typedef long int time_t;")
pcall(ffi.cdef, "typedef long int suseconds_t;")
pcall(ffi.cdef, [[
struct timeval {
  long int tv_sec;
  long int tv_usec;
};
]])
