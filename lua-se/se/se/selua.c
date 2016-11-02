#include "se.h"
#include <lualib.h>

int main(int argc, char **argv)
{
	lua_State *L;
	int err;

	if (argc != 2) {
		fprintf(stderr, "Usage: %s script [args]\n", argv[0]);
		exit(1);
	}

	L = luaL_newstate();
	oom_check(L);

	luaL_openlibs(L);

	err = luaL_dofile(L, argv[1]);
	if (err) {
		fprintf(stderr, "selua error [code=%d]: %s\n", err, lua_tostring(L, -1));
		lua_pop(L, 1);
	}

	lua_close(L);
	return err;
}