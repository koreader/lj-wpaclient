local ffi = require('ffi')

ffi.cdef[[
struct sockaddr {
  short unsigned int sa_family;
  char sa_data[14];
};
int socket(int, int, int) __attribute__((__nothrow__, __leaf__));
int bind(int, const struct sockaddr *, unsigned int) __attribute__((__nothrow__, __leaf__));
int connect(int, const struct sockaddr *, unsigned int);
long int recvfrom(int, void *restrict, size_t, int, struct sockaddr *restrict, unsigned int *restrict);
long int send(int, const void *, size_t, int);
int close(int);
]]
