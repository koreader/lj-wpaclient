local ffi = require("ffi")
local C = ffi.C

ffi.cdef[[
typedef long int __fd_mask;
typedef struct {
  __fd_mask __fds_bits[32];
} fd_set;
int select(int, fd_set *restrict, fd_set *restrict, fd_set *restrict, struct timeval *restrict);

static const int POLLRDNORM = 64;
static const int POLLRDBAND = 128;
]]

-- Most of this is handled via macros in C...
local __NFDBITS = 8 * ffi.sizeof("__fd_mask")
local function __FD_ELT(d)
    return math.floor(d / __NFDBITS)
end
local function __FD_MASK(d)
    return ffi.cast("__fd_mask", bit.lshift(1, d % __NFDBITS))
end

function C.FD_ZERO(s)
    for i = 0, ffi.sizeof("fd_set") / ffi.sizeof("__fd_mask") do
        s.__fds_bits[i] = 0
    end
end

function C.FD_SET(d, s)
    local fd_idx = __FD_ELT(d)
    s.__fds_bits[fd_idx] = bit.bor(s.__fds_bits[fd_idx], __FD_MASK(d))
end

function C.FD_CLR(d, s)
    local fd_idx = __FD_ELT(d)
    s.__fds_bits[fd_idx] = bit.band(s.__fds_bits[fd_idx], bit.bnot(__FD_MASK(d)))
end

function C.FD_ISSET(d, s)
    local fd_idx = __FD_ELT(d)
    return bit.band(s.__fds_bits[fd_idx], __FD_MASK(d)) ~= 0
end

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

-- To match FD_ISSET behavior with poll
C.POLLIN_SET = bit.bor(C.POLLRDNORM, C.POLLRDBAND, C.POLLIN, C.POLLHUP, C.POLLERR)
