#include <errno.h>
#include <poll.h>
#include <unistd.h>
#include <sys/un.h>
#include <sys/socket.h>

#include "ffi-cdecl.h"

// NOTE: Some of this may already be provided by our koreader-base ffi modules (in particular, posix),
//       hence the conditional loading in socket.lua

cdecl_const(AF_UNIX)
cdecl_const(SOCK_DGRAM)
cdecl_const(SOCK_NONBLOCK)
cdecl_const(SOCK_CLOEXEC)
cdecl_const(MSG_PEEK)
cdecl_const(MSG_NOSIGNAL)
cdecl_struct(sockaddr_un)
cdecl_struct(sockaddr)
cdecl_func(socket)
cdecl_func(bind)
cdecl_func(connect)
cdecl_func(recv)
cdecl_func(recvfrom)
cdecl_func(send)
cdecl_func(close)

cdecl_func(getpid)
cdecl_func(unlink)

cdecl_const(POLLIN)
cdecl_const(POLLOUT)
cdecl_const(POLLERR)
cdecl_const(POLLHUP)
cdecl_const(POLLRDNORM)
cdecl_const(POLLRDBAND)
cdecl_struct(pollfd)
cdecl_func(poll)

cdecl_const(EINTR)
cdecl_const(EAGAIN)
cdecl_const(EISCONN)
