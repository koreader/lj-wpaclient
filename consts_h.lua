local cur_path = (...):match("(.-)[^%(.|/)]+$")
local ffi = require("ffi")

-- Handle arch-dependent typedefs...
if ffi.arch == "mips" then
    require(cur_path .. "consts_mips_h")
else
    require(cur_path .. "consts_def_h")
end

pcall(ffi.cdef, "static const int AF_UNIX = 1;")
pcall(ffi.cdef, "static const int SOCK_CLOEXEC = 524288;")
pcall(ffi.cdef, "static const int MSG_PEEK = 2;")
pcall(ffi.cdef, "static const int MSG_NOSIGNAL = 16384;")
pcall(ffi.cdef, "static const int EINTR = 4;")
pcall(ffi.cdef, "static const int EAGAIN = 11;")
