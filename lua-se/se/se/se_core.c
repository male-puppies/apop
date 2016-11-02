#include "se_core.h"
#include "se_ev.h"
#include "se_socket.h"
#include "utils/list.h"
#include "utils/sds.h"


#if 1
#define printf(...) ((void)0)
#endif

struct se_thread {
	struct list_head node;
	lua_State *L;
	int lref;
	int nresult;
	ev_timer timer;
	ev_io io;
	sds buf;
	int nwrite;
};

static struct se_thread *se_current;
static struct se_thread se_main_thread;
static LIST_HEAD(se_running_threads);

#define se_assert(L, expr, ...) do { \
	if (!(expr)) \
		luaL_error(L, "se_assert(" #expr ") failed. " __VA_ARGS__); \
} while (0)

#define se_assert_arity(L, arity, ...) \
	se_assert(L, lua_gettop(L) == (arity), ##__VA_ARGS__)

#define se_assert_arity_range(L, min, max, ...) do { \
	int arity = lua_gettop(L); \
	se_assert(L, arity >= (min) && arity <= (max), ##__VA_ARGS__); \
} while (0)

#define SE_WAIT(L, narg, type, cb, ...) do { \
	struct se_thread *thread = se_current; \
	list_del(&thread->node); \
	ev_##type##_init(&thread->type, se_on_##cb, ##__VA_ARGS__); \
	ev_##type##_start(EV_DEFAULT_ &thread->type); \
	return lua_yield(L, (narg)); \
} while (0)

#define SE_WAIT_TIMEOUT(L, narg, timeout_arg, type, cb, ...) do { \
	struct se_thread *thread = se_current; \
	if (lua_gettop(L) - (narg) >= timeout_arg) { \
		lua_Number timeout = luaL_checknumber(L, timeout_arg); \
		if (timeout > 0.001) { \
			ev_timer_init(&thread->timer, se_on_##cb##_timeout, timeout, 0); \
			ev_timer_start(EV_DEFAULT_ &thread->timer); \
		} else if (timeout >= 0) { \
			break; \
		} \
	} \
	ev_##type##_init(&thread->type, se_on_##cb, ##__VA_ARGS__); \
	ev_##type##_start(EV_DEFAULT_ &thread->type); \
	list_del(&thread->node); \
	return lua_yield(L, (narg)); \
} while (0)

static void se_thread_wakeup(struct se_thread *thread, int nresult)
{
	list_add_tail(&thread->node, &se_running_threads);
	thread->nresult = nresult;
}

static void se_thread_wakeup_io(struct se_thread *thread, int nresult)
{
	if (ev_is_active(&thread->timer))
		ev_timer_stop(EV_DEFAULT_ &thread->timer);
	ev_io_stop(EV_DEFAULT_ &thread->io);
	se_thread_wakeup(thread, nresult);
}

static void se_thread_new(lua_State *L)
{
	struct se_thread *thread;

	luaL_checktype(L, 1, LUA_TFUNCTION);

	thread = se_new(struct se_thread);
	thread->L = lua_newthread(L);
	thread->lref = luaL_ref(L, LUA_REGISTRYINDEX); // prevent gc
	thread->buf = NULL;

	se_thread_wakeup(thread, lua_gettop(L) - 1);
	ev_init(&thread->timer, NULL);
	ev_init(&thread->io, NULL);
	ev_ref(EV_DEFAULT); // keep ev loop running until there is no thread exists

	//lua_pushvalue(L, 1);  /* move function to top */
  	lua_xmove(L, thread->L, lua_gettop(L));  /* move function and args from L to NL */
}

static void se_thread_free(lua_State *L, struct se_thread *thread)
{
	ev_unref(EV_DEFAULT);
	list_del(&thread->node);
	se_assert(L, !thread->buf);
	luaL_unref(L, LUA_REGISTRYINDEX, thread->lref);
	se_assert(L, !ev_is_active(&thread->timer));
	se_assert(L, !ev_is_active(&thread->io));
	se_free(thread);
}

static void se_thread_resume(lua_State *L, struct se_thread *thread)
{
	lua_State *co = thread->L;
	int status;

	if (lua_status(co) == LUA_OK && lua_gettop(co) == 0)
		luaL_error(L, "cannot resume dead coroutine");

	status = lua_resume(co, L, thread->nresult);
	switch (status) {
	case LUA_YIELD: // yield
		thread->nresult = 0;
		break;
	case LUA_OK: // finish
		se_thread_free(L, thread);
		break;
	default:
		lua_xmove(co, L, 1);  /* move error message */
		lua_error(L);
	}
}

static void se_on_schedule(EV_P_ ev_prepare *prepare, int revents)
{
	lua_State *L = prepare->data;
	struct se_thread *thread;

	while (!list_empty(&se_running_threads)) {
		thread = list_first_entry(&se_running_threads, struct se_thread, node);
		list_move_tail(&thread->node, &se_running_threads);
		se_current = thread;
		se_thread_resume(L, thread);
		se_current = &se_main_thread;
	}
}

static int se_schedule(lua_State *L)
{
	ev_prepare prepare;

	prepare.data = L;
	ev_prepare_init(&prepare, se_on_schedule);
	ev_prepare_start(EV_DEFAULT_ &prepare);
	ev_unref(EV_DEFAULT);

	ev_run(EV_DEFAULT_ 0);

	return 0;
}

int l_se_run(lua_State *L)
{
	se_main_thread.L = L;
	se_main_thread.lref = LUA_NOREF;

	se_current = &se_main_thread;

	se_thread_new(L);

	return se_schedule(L);
}

int l_se_go(lua_State *L)
{
	se_thread_new(L);
	return 0;
}

int l_se_time(lua_State *L)
{
	ev_now_update(EV_DEFAULT);
	lua_pushnumber(L, ev_now(EV_DEFAULT));
	return 1;
}

static void se_on_sleep(EV_P_ ev_timer *timer, int revents)
{
	struct se_thread *thread = container_of(timer, struct se_thread, timer);

	se_assert_arity(thread->L, 0);

	se_assert(thread->L, !ev_is_active(timer));
	se_thread_wakeup(thread, 0);
}

int l_se_sleep(lua_State *L)
{
	lua_Number timeout;

	se_assert_arity(L, 1, "invalid arguments, usage: sleep(second)");

	timeout = luaL_checknumber(L, 1);
	se_assert(L, timeout > 0, "invalid arguments, bad timeout: %f", timeout);

	SE_WAIT(L, 0, timer, sleep, timeout, 0);
}

int l_se_close(lua_State *L)
{
	int fd;

	se_assert_arity(L, 1, "invalid arguments, usage: close(fd)");

	fd = luaL_checkinteger(L, 1);

	if (close(fd) != 0) {
		se_assert(L, errno != EBADF, "close(%d) error", fd);
		lua_pushstring(L, strerror(errno));
		return 1;
	}

	return 0;
}

static int se_read_error(lua_State *L, sds *pcache, const char *errmsg)
{
	sds cache = *pcache;

	if (cache) {
		size_t len = sdslen(cache);
		if (len)
			lua_pushlstring(L, cache, sdslen(cache));
		else
			lua_pushnil(L);
		sdsfree(cache);
		*pcache = NULL;
	} else {
		lua_pushnil(L);
	}
	lua_pushstring(L, errmsg);
	return 2;
}

static int se_try_read(lua_State *L, int fd, int size, sds *pcache)
{
	char sbuf[4 << 10];
	char *cache = *pcache;
	char *buf;
	int bufsize;
	int nread;

	if (cache) {
		bufsize = sdsavail(cache);
		buf = cache + sdslen(cache);
		printf("continue try read: %d / %d\n", bufsize, size);
	} else { // first try
		bufsize = size > 0 ? size : size < 0 ? -size : sizeof(sbuf);
		if (bufsize <= sizeof(sbuf)) {
			buf = sbuf;
		} else {
			cache = sdsnewlen(NULL, bufsize);
			oom_check(cache);
			sdsclear(cache);
			*pcache = cache;
			buf = cache;
		}
		printf("try read: %d / %d\n", bufsize, size);
	}

	nread = read(fd, buf, bufsize);
	if (nread > 0) {
		if (size <= 0 || nread == bufsize) { // done
			if (cache) {
				lua_pushlstring(L, cache, sdslen(cache) + nread);
				sdsfree(cache);
				*pcache = NULL;
			} else {
				lua_pushlstring(L, buf, nread);
			}
			printf("read done: %d / %d / %d\n", nread, bufsize, size);
			return 1;
		}
		// partial read
		if (!cache) {
			cache = sdsnewlen(NULL, bufsize);
			oom_check(cache);
			sdsclear(cache);
			*pcache = cache;
			memcpy(cache, buf, nread);
		}
		sdsIncrLen(cache, nread);
		printf("partial read: %d / %d / %d\n", nread, bufsize, size);
		return -1;
	}

	if (nread == 0)
		return se_read_error(L, pcache, "EOF");

	if (errno == EAGAIN || errno == EWOULDBLOCK)
		return -1;

	se_assert(L, errno != EBADF, "read(%d) error", fd);
	return se_read_error(L, pcache, strerror(errno));
}

static void se_on_read(EV_P_ ev_io *io, int revents)
{
	struct se_thread *thread = container_of(io, struct se_thread, io);
	int nresult;

	se_assert_arity(thread->L, 0);

	nresult = se_try_read(thread->L, io->fd, (long)io->data, &thread->buf);
	if (nresult >= 0)
		se_thread_wakeup_io(thread, nresult);
}

static void se_on_read_timeout(EV_P_ ev_timer *timer, int revents)
{
	struct se_thread *thread = container_of(timer, struct se_thread, timer);

	se_assert_arity(thread->L, 0);
	se_thread_wakeup_io(thread, se_read_error(thread->L, &thread->buf, "TIMEOUT"));
}

int l_se_read(lua_State *L)
{
	int fd;
	int size;
	int nresult;

	se_assert_arity_range(L, 1, 3, "invalid arguments, usage: read(fd, size, timeout)");

	fd = luaL_checkinteger(L, 1);
	size = lua_tointeger(L, 2);

	se_assert(L, !se_current->buf);

	nresult = se_try_read(L, fd, size, &se_current->buf);
	if (nresult >= 0)
		return nresult;

	se_current->io.data = (void *)(long)size;
	SE_WAIT_TIMEOUT(L, 0, 3, io, read, fd, EV_READ);

	return se_read_error(L, &se_current->buf, "TIMEOUT");
}

static int se_write_error(lua_State *L, int nwrite, const char *errmsg)
{
	lua_pushstring(L, errmsg);
	lua_pushinteger(L, nwrite);
	return 2;
}

static int se_try_write(lua_State *L, int fd, const char *data, int size, int *pnwrite)
{
	const char *buf = data + *pnwrite;
	int bufsize = size - *pnwrite;
	int nwrite;

	printf("try write: %d / %d\n", bufsize, size);

	nwrite = write(fd, buf, bufsize);
	if (nwrite == bufsize) {
		printf("write done: %d / %d\n", bufsize, size);
		return 0;
	}

	if (nwrite > 0) {
		printf("partial written: %d / %d / %d\n", nwrite, bufsize, size);
		*pnwrite += nwrite;
		return -1;
	}

	if (nwrite == 0)
		return -1;

	if (errno == EAGAIN || errno == EWOULDBLOCK)
		return -1;

	se_assert(L, errno != EBADF, "write(%d) error", fd);
	return se_write_error(L, *pnwrite, strerror(errno));
}

static void se_on_write(EV_P_ ev_io *io, int revents)
{
	struct se_thread *thread = container_of(io, struct se_thread, io);
	const char *data;
	size_t size;
	int nresult;

	se_assert_arity(thread->L, 1);

	data = lua_tolstring(thread->L, 1, &size);

	nresult = se_try_write(thread->L, io->fd, data, size, &thread->nwrite);
	if (nresult >= 0)
		se_thread_wakeup_io(thread, nresult);
}

static void se_on_write_timeout(EV_P_ ev_timer *timer, int revents)
{
	struct se_thread *thread = container_of(timer, struct se_thread, timer);

	se_assert_arity(thread->L, 1);
	se_thread_wakeup_io(thread, se_write_error(thread->L, thread->nwrite, "TIMEOUT"));
}

int l_se_write(lua_State *L)
{
	struct se_thread *thread = se_current;
	int fd;
	const char *data;
	size_t size;
	int nresult;

	se_assert_arity_range(L, 2, 3, "invalid arguments, usage: write(fd, data, timeout)");

	fd = luaL_checkinteger(L, 1);
	luaL_checktype(L, 2, LUA_TSTRING);
	data = lua_tolstring(L, 2, &size);

	if (size == 0)
		return 0;

	thread->nwrite = 0;

	nresult = se_try_write(L, fd, data, size, &thread->nwrite);
	if (nresult >= 0)
		return nresult;

	lua_pushvalue(L, 2);
	SE_WAIT_TIMEOUT(L, 1, 3, io, write, fd, EV_WRITE);

	return se_write_error(L, thread->nwrite, "TIMEOUT");
}

static int se_connect_error(lua_State *L, const char *errmsg)
{
	lua_pushnil(L);
	lua_pushstring(L, errmsg);
	return 2;
}

static void se_on_connect(EV_P_ ev_io *io, int revents)
{
	struct se_thread *thread = container_of(io, struct se_thread, io);
	int err;

	se_assert_arity(thread->L, 0);

	err = se_socket_error(io->fd);
	if (err) {
		se_thread_wakeup_io(thread, se_connect_error(thread->L, strerror(err)));
		close(io->fd);
	} else {
		lua_pushinteger(thread->L, io->fd);
		se_thread_wakeup_io(thread, 1);
	}
}

static void se_on_connect_timeout(EV_P_ ev_timer *timer, int revents)
{
	struct se_thread *thread = container_of(timer, struct se_thread, timer);

	se_assert_arity(thread->L, 0);
	se_thread_wakeup_io(thread, se_connect_error(thread->L, "TIMEOUT"));
	close(thread->io.fd);
}

int l_se_connect(lua_State *L)
{
	const char *addr;
	int fd;
	int err;

	se_assert_arity_range(L, 1, 2, "invalid arguments, usage: connect(addr, timeout)");

	luaL_checktype(L, 1, LUA_TSTRING);
	addr = lua_tostring(L, 1);

	err = se_socket_connect(addr, &fd);
	if (err) {
		if (fd < 0)
			return se_connect_error(L, strerror(err));
		SE_WAIT_TIMEOUT(L, 0, 2, io, connect, fd, EV_WRITE);
		close(fd);
		return se_connect_error(L, "TIMEOUT");
	}

	lua_pushinteger(L, fd);
	return 1;
}

int l_se_listen(lua_State *L)
{
	const char *addr;
	int fd;
	int err;

	se_assert_arity(L, 1, "invalid arguments, usage: listen(addr)");

	luaL_checktype(L, 1, LUA_TSTRING);
	addr = lua_tostring(L, 1);

	err = se_socket_listen(addr, &fd);
	if (err) {
		lua_pushnil(L);
		lua_pushstring(L, strerror(err));
		return 2;
	}

	lua_pushinteger(L, fd);
	return 1;
}

static int se_accept_error(lua_State *L, const char *errmsg)
{
	lua_pushnil(L);
	lua_pushstring(L, errmsg);
	return 2;
}

static int se_try_accept(lua_State *L, int fd)
{
	int newfd;
	int err;

	err = se_socket_accept(fd, &newfd);
	if (err) {
		if (err == EAGAIN || err == EWOULDBLOCK)
			return -1;
		se_assert(L, err != EBADF, "accept(%d) error", fd);
		return se_accept_error(L, strerror(err));
	}

	lua_pushinteger(L, newfd);
	return 1;
}

static void se_on_accept(EV_P_ ev_io *io, int revents)
{
	struct se_thread *thread = container_of(io, struct se_thread, io);
	int nresult;

	se_assert_arity(thread->L, 0);

	nresult = se_try_accept(thread->L, io->fd);
	if (nresult >= 0)
		se_thread_wakeup_io(thread, nresult);
}

static void se_on_accept_timeout(EV_P_ ev_timer *timer, int revents)
{
	struct se_thread *thread = container_of(timer, struct se_thread, timer);

	se_assert_arity(thread->L, 0);
	se_thread_wakeup_io(thread, se_accept_error(thread->L, "TIMEOUT"));
}

int l_se_accept(lua_State *L)
{
	int fd;
	int nresult;

	se_assert_arity_range(L, 1, 2, "invalid arguments, usage: accept(fd, timeout)");

	fd = luaL_checkinteger(L, 1);

	nresult = se_try_accept(L, fd);
	if (nresult >= 0)
		return nresult;

	SE_WAIT_TIMEOUT(L, 0, 2, io, accept, fd, EV_READ);

	return se_accept_error(L, "TIMEOUT");
}

int l_se_shutdown(lua_State *L)
{
	int fd;
	int how;
	int err;

	se_assert_arity(L, 2, "invalid arguments, usage: shutdown(fd, how)");

	fd = luaL_checkinteger(L, 1);
	how = luaL_checkinteger(L, 2);

	err = se_socket_shutdown(fd, how);
	if (err) {
		se_assert(L, err != EBADF, "shutdown(%d) error", fd);
		lua_pushstring(L, strerror(err));
		return 1;
	}

	return 0;
}

static int se_getsockaddr(lua_State *L, int (*fn)(int, struct sockaddr *, socklen_t *))
{
	int fd;
	char ip[SE_IP_MAX_LENGTH];
	uint16_t port;

	se_assert_arity(L, 1, "invalid arguments, usage: getsockaddr(fd)");

	fd = luaL_checkinteger(L, 1);

	se_socket_addr(fn, fd, ip, &port);

	lua_newtable(L);
	lua_pushstring(L, ip);
	lua_setfield(L, -2, "ip");
	lua_pushinteger(L, port);
	lua_setfield(L, -2, "port");
	return 1;
}

int l_se_getsockname(lua_State *L)
{
	return se_getsockaddr(L, getsockname);
}

int l_se_getpeername(lua_State *L)
{
	return se_getsockaddr(L, getpeername);
}
