local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require("ffi")

-- Handle arch-dependent typedefs...
if ffi.abi("64bit") then
    require(cur_path .. "select_64b_h")
else
    require(cur_path .. "select_def_h")
end
pcall(ffi.cdef, "int select(int, fd_set *restrict, fd_set *restrict, fd_set *restrict, struct timeval *restrict);")

pcall(ffi.cdef, "static const int POLLRDNORM = 64;")
pcall(ffi.cdef, "static const int POLLRDBAND = 128;")


--[[
#define __NFDBITS    (8 * (int) sizeof (__fd_mask))
#define>__FD_ELT(d)  ((d) / __NFDBITS)
#define>__FD_MASK(d) ((__fd_mask) (1UL << ((d) % __NFDBITS)))

#define __FDS_BITS(set) ((set)->__fds_bits)

#define __FD_ZERO(s) \
  do {                                                                        \
    unsigned int __i;                                                         \
    fd_set *__arr = (s);                                                      \
    for (__i = 0; __i < sizeof (fd_set) / sizeof (__fd_mask); ++__i)          \
      __FDS_BITS (__arr)[__i] = 0;                                            \
  } while (0)
#define __FD_SET(d, s) \
  ((void) (__FDS_BITS (s)[__FD_ELT(d)] |= __FD_MASK(d)))
#define __FD_CLR(d, s) \
  ((void) (__FDS_BITS (s)[__FD_ELT(d)] &= ~__FD_MASK(d)))
#define __FD_ISSET(d, s) \
  ((__FDS_BITS (s)[__FD_ELT (d)] & __FD_MASK (d)) != 0)
--]]
