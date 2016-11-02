#include "se_socket.h"

int se_socket_addr(int (*fn)(int, struct sockaddr *, socklen_t *),
				int sock, char *ip, uint16_t *port)
{
	union {
		struct sockaddr sa;
		struct sockaddr_storage ss;
		struct sockaddr_in in4;
		struct sockaddr_in6 in6;
	} sock_addr;
	socklen_t sock_len = sizeof(sock_addr);
	const void *ip_addr;
	int err;

	err = fn(sock, &sock_addr.sa, &sock_len);
	if (err)
		goto fail;

	switch (sock_addr.ss.ss_family) {
	case AF_INET:
		ip_addr = &sock_addr.in4.sin_addr;
		*port = ntohs(sock_addr.in4.sin_port);
		break;
	case AF_INET6:
		ip_addr = &sock_addr.in6.sin6_addr;
		*port = ntohs(sock_addr.in6.sin6_port);
		break;
	default:
		goto fail;
	}

	if (!inet_ntop(sock_addr.ss.ss_family, ip_addr, ip, SE_IP_MAX_LENGTH))
		goto fail;

	return 0;
fail:
	ip[0] = 0;
	*port = 0;
	return EINVAL;
}

static int se_parse_ipv4_addr(const char *addr, struct sockaddr_in *out)
{
	const char *colon;
	int port;
	int ip_len;
	char ip_str[SE_IP_MAX_LENGTH];

	colon = strchr(addr, ':');
	if (!colon)
		return EINVAL;

	port = atoi(colon + 1);
	if (port < 0 || port > 65535)
		return EINVAL;

	ip_len = colon - addr;
	if (ip_len >= sizeof(ip_str))
		return EINVAL;

	memcpy(ip_str, addr, ip_len);
	ip_str[ip_len] = 0;

	out->sin_family = AF_INET;
	out->sin_port = htons(port);
	return inet_pton(AF_INET, ip_str, &out->sin_addr.s_addr) == 1 ? 0 : EINVAL;
}

static int se_parse_addr(const char *addr,
						int *sock_type,
						struct sockaddr_storage *sock_addr,
						socklen_t *sock_size)
{
	const char *colon;
	int family;

	colon = strstr(addr, "://");
	if (!colon)
		return EINVAL;

	switch (colon - addr) {
	case 3:
		if (memcmp(addr, "tcp", 3) == 0)
			*sock_type = SOCK_STREAM;
		else if (memcmp(addr, "udp", 3) == 0)
			*sock_type = SOCK_DGRAM;
		else
			return EINVAL;
		family = AF_INET;
		break;
	case 4:
		if (memcmp(addr, "unix", 4) == 0)
			*sock_type = SOCK_STREAM;
		else
			return EINVAL;
		family = AF_UNIX;
		break;
	case 8:
		if (memcmp(addr, "unixgram", 8) == 0)
			*sock_type = SOCK_DGRAM;
		else
			return EINVAL;
		family = AF_UNIX;
		break;
	default:
		return EINVAL;
	}

	addr = colon + 3; // skip "://"

	switch (family) {
	case AF_INET:
		*sock_size = sizeof(struct sockaddr_in);
		return se_parse_ipv4_addr(addr, (struct sockaddr_in *)sock_addr);
	case AF_INET6:
		*sock_size = sizeof(struct sockaddr_in6);
		return EINVAL;
	case AF_UNIX:
		return EINVAL;
	}

	return EINVAL;
}

static int se_socket_config(int sock)
{
	int on = 1;

	if (setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &on, sizeof(on)) < 0) {
		if (errno != ENOPROTOOPT && errno != EOPNOTSUPP) // maybe unix domain socket
			return errno;
	}

	return 0;
}

static int se_socket_create(int domain, int type, int *psock)
{
	int sock;
	int err;

	sock = socket(domain, type | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (sock < 0)
		return errno;

	err = se_socket_config(sock);
	if (err) {
		close(sock);
		return err;
	}

	*psock = sock;
	return 0;
}

int se_socket_error(int sock)
{
	int err;
	int sockerr;
	socklen_t sockerr_len = sizeof(sockerr);

	err = getsockopt(sock, SOL_SOCKET, SO_ERROR, &sockerr, &sockerr_len);
	if (err)
		return errno;

	if (sockerr_len != sizeof(sockerr))
		return EINVAL;

	return sockerr;
}

int se_socket_connect(const char *addr, int *psock)
{
	struct sockaddr_storage sock_addr;
	socklen_t sock_size;
	int sock_type;
	int sock;
	int err;

	*psock = -1;

	err = se_parse_addr(addr, &sock_type, &sock_addr, &sock_size);
	if (err)
		return err;

	err = se_socket_create(sock_addr.ss_family, sock_type, &sock);
	if (err)
		return err;

	err = connect(sock, (const struct sockaddr *)&sock_addr, sock_size);
	if (err) {
		err = errno;
		if (err != EINPROGRESS)
			close(sock);
		else
			*psock = sock;
		return err;
	}

	*psock = sock;
	return 0;
}

static int se_socket_bind(int sock, const struct sockaddr *sock_addr, socklen_t sock_size)
{
	int value = 1;
	int err;

	err = setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &value, sizeof(value));
	if (err)
		return errno;

	err = bind(sock, sock_addr, sock_size);
	if (err)
		return errno;

    return 0;
}

int se_socket_listen(const char *addr, int *psock)
{
	struct sockaddr_storage sock_addr;
	socklen_t sock_size;
	int sock_type;
	int sock;
	int err;

	*psock = -1;

	err = se_parse_addr(addr, &sock_type, &sock_addr, &sock_size);
	if (err)
		return err;

	err = se_socket_create(sock_addr.ss_family, sock_type, &sock);
	if (err)
		return err;

	err = se_socket_bind(sock, (const struct sockaddr *)&sock_addr, sock_size);
	if (err) {
		close(sock);
		return err;
	}

	err = listen(sock, 512);
	if (err) {
		err = errno;
		close(sock);
		return err;
	}

	*psock = sock;
	return 0;
}

int se_socket_accept(int sock, int *pnewsock)
{
	int newsock;
	int err;

	newsock = accept4(sock, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
	if (newsock < 0)
		return errno;

	err = se_socket_config(newsock);
	if (err) {
		close(newsock);
		return err;
	}

	*pnewsock = newsock;
	return 0;
}

int se_socket_shutdown(int sock, int how)
{
	int err;

	err = shutdown(sock, how);
	if (err)
		return errno;

	return 0;
}