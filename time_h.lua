local ffi = require("ffi")

ffi.cdef[[
typedef long int time_t;
typedef long int suseconds_t;
struct timeval {
  long int tv_sec;
  long int tv_usec;
};
]]
