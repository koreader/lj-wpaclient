local ffi = require("ffi")

pcall(ffi.cdef, "static const int POLLIN = 1;")
pcall(ffi.cdef, "static const int POLLOUT = 4;")
pcall(ffi.cdef, "static const int POLLERR = 8;")
pcall(ffi.cdef, "static const int POLLHUP = 16;")
pcall(ffi.cdef, "static const int POLLRDNORM = 64;")
pcall(ffi.cdef, "static const int POLLRDBAND = 128;")
pcall(ffi.cdef, [[
struct pollfd {
  int fd;
  short int events;
  short int revents;
};
]])
pcall(ffi.cdef, "int poll(struct pollfd *, long unsigned int, int);")
