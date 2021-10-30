#include <errno.h>
#include <unistd.h>
#include <sys/un.h>
#include <sys/socket.h>
#include <poll.h>
#include <sys/select.h>

#include "ffi-cdecl.h"

// NOTE: Some of this may already be provided by our koreader-base ffi modules (in particular, posix),
//       hence the conditional loading in socket.lua

cdecl_const(AF_UNIX)
cdecl_const(SOCK_DGRAM)
cdecl_const(SOCK_NONBLOCK)
cdecl_const(SOCK_CLOEXEC)
cdecl_const(MSG_PEEK)
cdecl_struct(sockaddr_un)
cdecl_struct(sockaddr)
cdecl_func(socket)
cdecl_func(bind)
cdecl_func(connect)
cdecl_func(recv)
cdecl_func(recvfrom)
cdecl_func(send)
cdecl_func(close)

cdecl_func(unlink)

cdecl_const(POLLIN)
cdecl_struct(pollfd)
cdecl_func(poll)

cdecl_type(__fd_mask)
cdecl_type(fd_set)
cdecl_func(select)

cdecl_type(time_t)
cdecl_type(suseconds_t)
cdecl_struct(timeval)

cdecl_const(EINTR)
cdecl_const(EISCONN)
