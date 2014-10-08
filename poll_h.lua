local ffi = require("ffi")

ffi.cdef[[
static const int POLLIN = 1;
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
int poll(struct pollfd *, long unsigned int, int);
]]
