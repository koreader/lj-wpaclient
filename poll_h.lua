local ffi = require("ffi")

pcall(ffi.cdef, "static const int POLLIN = 1;")
pcall(ffi.cdef, [[
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
]])
pcall(ffi.cdef, "int poll(struct pollfd *, long unsigned int, int);")
