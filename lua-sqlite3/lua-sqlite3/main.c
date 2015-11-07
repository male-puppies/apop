#include <stdlib.h>
#include <string.h>
#include <assert.h>

#include "luacommon.h"
#include "sqlite3.h"


#define MT_SQLITE3 	"mt_sqlite3"

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
	memset(db, 0, sizeof(struct sdb));
	
	if (sqlite3_open(filename, &db->db) == SQLITE_OK) {
		luaL_getmetatable(L, MT_SQLITE3);
		lua_setmetatable(L, -2);
		return 1;
	}

	lua_pushnil(L);
	lua_pushstring(L, sqlite3_errmsg(db->db));
	cleanupdb(L, db);

	return 2;
}

struct cb_help {
	int i;
	lua_State *L;
};

static int callback(void *data, int argc, char **argv, char **azColName){
	struct cb_help *h = (struct cb_help *)data;

	lua_State *L = h->L;
	lua_newtable(L);

	int i;
	for (i = 0; i < argc; i++) {
		if (argv[i]) {
			lua_pushstring(L, argv[i]);
		} else {
			lua_pushnil(L);
		}
		lua_rawseti(L, -2, i + 1);
	}

	lua_rawseti(L, -2, ++(h->i));
	return 0;
}

static int lsqlite_exec(lua_State *L) { 
	struct sdb *db = (struct sdb *)luaL_checkudata(L, 1, MT_SQLITE3);
	const char *sql = luaL_checkstring(L, 2);
	
	if (lua_isboolean(L, 3) && lua_toboolean(L, 3)) { 	//have result 
		lua_newtable(L);
		
		char *errmsg = NULL;
		struct cb_help help = {0, L};
		
		int ret = sqlite3_exec(db->db, sql, callback, &help, &errmsg);
		if (ret != SQLITE_OK) {
			lua_pop(L, 1); 		DUMP(L);
			lua_pushnil(L);
			lua_pushstring(L, errmsg);
			sqlite3_free(errmsg); DUMP(L);
			return 2; 
		}
		return 1;
	} 

	char *errmsg = NULL;
	int ret = sqlite3_exec(db->db, sql, 0, 0, &errmsg);
	if (ret != SQLITE_OK) {
		lua_pushnil(L); 		DUMP(L);
		lua_pushstring(L, errmsg);
		sqlite3_free(errmsg);	DUMP(L);
		return 2; 
	}

	lua_pushboolean(L, 1);
	
	return 1;
}

static int lsqlite_close(lua_State *L) {
	struct sdb *db = (struct sdb *)luaL_checkudata(L, 1, MT_SQLITE3);
	if (db->db) {
		cleanupdb(L, db);
		DUMP(L);
	}
	return 0;
}

static const luaL_Reg mt_sqlite[] = {
	{ "exec", 	lsqlite_exec },
	{ "close", 	lsqlite_close },
	{ "__gc", 	lsqlite_close },
	{ NULL, 	NULL}
};

static const luaL_Reg sqlitelib[] = {
	{ "open",	lsqlite_open },
	{ NULL, 	NULL}
};

LUALIB_API int luaopen_lsqlite3(lua_State *L) {
	create_metatable(L, mt_sqlite, MT_SQLITE3);
	luaL_newlib(L, sqlitelib);
	return 1;
}





