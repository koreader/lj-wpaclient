#include <errno.h>
#include <unistd.h>
#include <sys/un.h>
#include <sys/socket.h>
#include <poll.h>

#include "ffi-cdecl.h"

cdecl_const(EINTR)
cdecl_const(AF_UNIX)
cdecl_const(SOCK_DGRAM)
cdecl_const(MSG_PEEK)
cdecl_struct(sockaddr_un)
cdecl_struct(sockaddr)
cdecl_func(socket)
cdecl_func(bind)
cdecl_func(connect)
cdecl_func(recvfrom)
cdecl_func(send)
cdecl_func(close)

cdecl_func(unlink)

cdecl_const(POLLIN)
cdecl_struct(pollfd)
cdecl_func(poll)
