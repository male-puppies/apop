#include <stdlib.h>
#include <string.h>
#include <assert.h>

#define LUA_LIB
#include "lua.h"
#include "lauxlib.h"
#include "sqlite3.h"

#if LUA_VERSION_NUM < 502 
# define luaL_newlib(L,l) (lua_newtable(L), luaL_register(L,NULL,l))
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

struct sdb {
	sqlite3 *db;
};

static void cleanupdb(lua_State *L, struct sdb *db) {
	sqlite3_close(db->db);
	db->db = NULL;
}

static int lsqlite_open(lua_State *L) {
	const char *filename = luaL_checkstring(L, 1);
	struct sdb *db = (struct sdb *)lua_newuserdata(L, sizeof(struct sdb));
	db->db = NULL;
	if (sqlite3_open(filename, &db->db) == SQLITE_OK) 
		return 1;

	cleanupdb(L, db);	
	lua_pushnil(L);
	// lua_pushinteger(L, sqlite3_errcode(db->db));
	lua_pushstring(L, sqlite3_errmsg(db->db));
	return 2;
}

struct cb_help {
	lua_State *L;
	int i;
};

static int callback(void *data, int argc, char **argv, char **azColName){
	struct cb_help *h = (struct cb_help *)data;

	lua_State *L = h->L;
	lua_newtable(L);

	int i;
	for (i = 0; i < argc; i++) {
		if (argv[i]) 
			lua_pushstring(L, argv[i]);
		else 
			lua_pushnil(L);
		lua_rawseti(L, -2, i + 1);
	}

	lua_rawseti(L, -2, ++(h->i));
	return 0;
}

static int lsqlite_exec(lua_State *L) {
	if (!lua_isuserdata(L, 1)) 
		luaL_error(L, "param 1 should be userdata");
	
	char *errmsg = NULL;
	struct sdb *db = (struct sdb *)lua_touserdata(L, 1);
	const char *sql = luaL_checkstring(L, 2);
	
	int is_select = 0;
	if (lua_isboolean(L, 3) && lua_toboolean(L, 3)) 
		is_select = 1;
	
	if (is_select) 
		lua_newtable(L);

	struct cb_help help = {L, 0};
	int ret = sqlite3_exec(db->db, sql, callback, &help, &errmsg);
	if (ret != SQLITE_OK) {
		lua_pop(L, 1);
		lua_pushnil(L);
		lua_pushstring(L, errmsg);
		sqlite3_free(errmsg);
		return 2; 
	}

	if (!is_select) 
		lua_pushboolean(L, 1);
	
	return 1;
}

static int lsqlite_close(lua_State *L) {
	if (!lua_isuserdata(L, 1)) 
		luaL_error(L, "param 1 should be userdata");
	struct sdb *db = (struct sdb *)lua_touserdata(L, 1); 	assert(db->db);
	cleanupdb(L, db);
	return 0;
}

static const luaL_Reg sqlitelib[] = {
	{ "open",	lsqlite_open },
	{ "exec", 	lsqlite_exec },
	{ "close", 	lsqlite_close },
	{ NULL, 	NULL}
};

#ifdef BY_LUA_53
LUALIB_API int luaopen_lsqlite53(lua_State *L) {
#else
LUALIB_API int luaopen_lsqlite(lua_State *L) {
#endif  
	luaL_newlib(L, sqlitelib); 
	return 1;
}





