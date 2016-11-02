#pragma once

#include "se.h"

#define SE_IP_MAX_LENGTH	64

int se_socket_error(int sock);
int se_socket_connect(const char *addr, int *psock);
int se_socket_listen(const char *addr, int *psock);
int se_socket_accept(int sock, int *pnewsock);
int se_socket_shutdown(int sock, int how);
int se_socket_addr(int (*fn)(int, struct sockaddr *, socklen_t *),
				int sock, char *ip, uint16_t *port);
