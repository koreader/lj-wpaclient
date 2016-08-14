local ffi = require('ffi')

ffi.cdef[[
static const int AF_UNIX = 1;
static const int SOCK_DGRAM = 2;
]]
