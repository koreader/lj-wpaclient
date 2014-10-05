#include <unistd.h>
#include <sys/un.h>
#include <sys/socket.h>
#include <sys/epoll.h>

#include "ffi-cdecl.h"
#include "ffi-cdecl-luajit.h"

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

cdecl_const(EPOLLIN)
cdecl_const(EPOLL_CTL_ADD)
cdecl_union(epoll_data)
cdecl_struct(epoll_event)
cdecl_func(epoll_create)
cdecl_func(epoll_ctl)
cdecl_func(epoll_wait)
