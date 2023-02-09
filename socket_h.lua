local ffi = require("ffi")

pcall(ffi.cdef, [[
struct sockaddr {
  short unsigned int sa_family;
  char sa_data[14];
};
]])
pcall(ffi.cdef, "int socket(int, int, int) __attribute__((nothrow, leaf));")
pcall(ffi.cdef, "int bind(int, const struct sockaddr *, unsigned int) __attribute__((nothrow, leaf));")
pcall(ffi.cdef, "int connect(int, const struct sockaddr *, unsigned int);")
pcall(ffi.cdef, "ssize_t recvfrom(int, void *restrict, size_t, int, struct sockaddr *restrict, unsigned int *restrict);")
pcall(ffi.cdef, "ssize_t recv(int, void *, size_t, int);")
pcall(ffi.cdef, "ssize_t send(int, const void *, size_t, int);")
pcall(ffi.cdef, "int close(int);")
