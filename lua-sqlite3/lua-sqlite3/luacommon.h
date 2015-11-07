#ifndef __LUA_COMMON_H__
#define __LUA_COMMON_H__

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#if LUA_VERSION_NUM >= 503 /* Lua 5.3 */
	#ifndef luaL_optlong
		#define luaL_optlong luaL_optinteger
	#endif
#endif


#if LUA_VERSION_NUM < 502
	#define LUA_OK	0
	#define lua_rawlen lua_objlen
	/* lua_...uservalue: Something very different, but it should get the job done */
	#define lua_getuservalue lua_getfenv
	#define lua_setuservalue lua_setfenv
	#define luaL_newlib(L,l) (lua_newtable(L), luaL_register(L,NULL,l))
	#define luaL_setfuncs(L,l,n) (assert(n==0), luaL_register(L,NULL,l))
	#define lua_resume(L,F,n) lua_resume(L,n)
#endif

#if LUA_VERSION_NUM > 501
	/*
	** Lua 5.2
	*/
	#define lua_strlen lua_rawlen
	/* luaL_typerror always used with arg at ndx == NULL */
	#define luaL_typerror(L,ndx,str) luaL_error(L,"bad argument %d (%s expected, got nil)",ndx,str)
	/* luaL_register used once, so below expansion is OK for this case */
	#define luaL_register(L,name,reg) lua_newtable(L);luaL_setfuncs(L,reg,0)
	/* luaL_openlib always used with name == NULL */
	#define luaL_openlib(L,name,reg,nup) luaL_setfuncs(L,reg,nup)

	#if LUA_VERSION_NUM > 502
		/*
		** Lua 5.3
		*/
		#define luaL_checkint(L,n)  ((int)luaL_checkinteger(L, (n)))
	#endif
#endif

void create_metatable(lua_State *L, const luaL_Reg *reg, const char *mt_name) {
	luaL_newmetatable(L, mt_name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_register(L, NULL, reg);
	lua_pop(L, 1);
}

#define DUMP(L) dump(L, __FILE__, __LINE__);
static void dump(lua_State *L, const char *file, int line) {
	int i;
	int top = lua_gettop(L);
	printf("%s %d\t", file, line);
	for (i = 1; i <= top; i++) {
		int t = lua_type(L, i);
		switch(t) {
		case LUA_TSTRING: 			printf("string:%s\t", lua_tostring(L, i)); break;
		case LUA_TBOOLEAN: 			printf("bool:%d\t", lua_toboolean(L, i)); break;
		case LUA_TNUMBER: 			printf("number:%g\t", lua_tonumber(L, i)); break; 
		case LUA_TNIL: 				printf("nil\t"); break;
		case LUA_TLIGHTUSERDATA: 	printf("luser\t"); break;
		case LUA_TTABLE: 			printf("table\t"); break; 
		case LUA_TFUNCTION: 		printf("func\t"); break;
		case LUA_TUSERDATA: 		printf("user\t"); break;
		case LUA_TTHREAD: 			printf("thread\t"); break; 
		default: 					printf("error:%s\t", lua_typename(L, i)); break; 
		}
	}
	printf("\n");
}

#define PFENV(L) pt(L, __FILE__, __LINE__)
static void pt(lua_State *L, const char *file, int line) {
	printf("trans table %s %d\n", file, line);
	lua_pushnil(L);
	while (lua_next(L, -2)) {
		printf("%g:%s\n", lua_tonumber(L, -2), lua_typename(L, lua_type(L, -1)));
		lua_pop(L, 1);
	}
}

#endif 