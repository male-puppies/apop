#include "se.h"
#include "se_core.h"


#define SE_API(name) { #name, l_se_##name },

static luaL_Reg l_se_library[] = {
	SE_API(run)
	SE_API(go)
	SE_API(time)
	SE_API(sleep)
	SE_API(close)
	SE_API(read)
	SE_API(write)
	SE_API(connect)
	SE_API(listen)
	SE_API(accept)
	SE_API(shutdown)
	SE_API(getsockname)
	SE_API(getpeername)
	{ NULL, NULL }
};

#undef SE_API


#ifdef _WIN32
void se_platform_init()
{}
#else
#include <sys/resource.h>
void se_platform_init()
{
	if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
		fprintf(stderr, "signal(SIGPIPE, SIG_IGN) error: %s\n", strerror(errno));
		abort();
	}

	struct rlimit rl = { 1 << 20, 1 << 20 };
	if (setrlimit(RLIMIT_NOFILE, &rl) != 0) {
		fprintf(stderr, "setrlimit(RLIMIT_NOFILE) error: %s\n", strerror(errno));
		abort();
	}
}
#endif


LUALIB_API int luaopen_se(lua_State *L)
{
	se_platform_init();
	luaL_newlib(L, l_se_library);
	return 1;
}