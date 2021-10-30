local ffi = require("ffi")

ffi.cdef[[
struct sockaddr {
  short unsigned int sa_family;
  char sa_data[14];
};
int socket(int, int, int) __attribute__((nothrow, leaf));
int bind(int, const struct sockaddr *, unsigned int) __attribute__((nothrow, leaf));
int connect(int, const struct sockaddr *, unsigned int);
ssize_t recvfrom(int, void *restrict, size_t, int, struct sockaddr *restrict, unsigned int *restrict);
ssize_t recv(int, void *, size_t, int);
ssize_t send(int, const void *, size_t, int);
int close(int);
]]
