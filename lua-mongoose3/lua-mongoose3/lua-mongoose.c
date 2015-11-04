#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h> 
#include "mongoose.h"  

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

#include "dump.c"

#define MODULE_MONGOOSE "mongoose"
#define META_MONGOOSE	"mongoose_mt"
#define META_LUA_CONN	"luaconn_mt"
#define META_HTTP_MSG 	"http_message_mt"
#define MAX_ROOT_SIZE 	(260)


struct httpserver {
	lua_State *L;
	struct mg_mgr mgr;
	struct mg_connection *nc; 
	struct mg_serve_http_opts opts;
	char root[MAX_ROOT_SIZE];
};

struct luaconn {
	void *p;
	struct mg_connection *nc; 
};

struct luahttpmsg {
	struct http_message *hm;
};

static int l_ip(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	lua_pushfstring(L, "%s", inet_ntoa(conn->nc->sa.sin.sin_addr));
	return 1;
}

static int l_addr(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	lua_pushfstring(L, "%p", conn->nc);
	return 1;
}

static int l_send(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	size_t len = 0;
	const char *s = lua_tolstring(L, 2, &len);
	mg_send(conn->nc, s, len);
	return 0;
}

static int l_send_close(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	conn->nc->flags |= MG_F_SEND_AND_CLOSE;
	return 0;
}

static int l_serve_http(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	struct httpserver *hs = (struct httpserver *)conn->nc->mgr->user_data;
	mg_serve_http(conn->nc, conn->p, hs->opts);
	return 0;
}

static int l_http_message(lua_State *L) {
	struct luaconn *conn = (struct luaconn *)luaL_checkudata(L, 1, META_LUA_CONN);
	struct http_message *hm = (struct http_message *)conn->p;
	if (!hm) {
		lua_pushnil(L);
		lua_pushstring(L, "not http_message");
		return 2;
	}
	
	struct luahttpmsg *hp = lua_newuserdata(L, sizeof(struct luahttpmsg));
	hp->hm = (struct http_message *)conn->p;
	luaL_getmetatable(L, META_HTTP_MSG); 
	lua_setmetatable(L, -2);
	return 1;
}

static int http_var_common(lua_State *L, const char *type) {
	struct luahttpmsg *hp = (struct luahttpmsg *)luaL_checkudata(L, 1, META_HTTP_MSG);
	const char *key = luaL_checkstring(L, 2);
	int len = 256;
	if (lua_isnumber(L, 3)) {
		len = lua_tointeger(L, 3);
		len = len > 0 ? len : 256;
	}
	
	char *buff = (char *)malloc(len); 	assert(buff);
	
	int ret;
	const struct mg_str *s = NULL;
	if (!strncmp(type, "body", 4)) {
		s = &hp->hm->body;
	} else if (!strncmp(type, "query_string", sizeof("query_string") - 1)) {
		s = &hp->hm->query_string;
	} 
	ret = mg_get_http_var(s, key, buff, len);
	if (ret <= 0) {
		lua_pushnil(L); 
		free(buff);
		return 1;
	}
	
	lua_pushfstring(L, "%s", buff);
	free(buff);
	return 1; 
}

static int l_uri(lua_State *L) {
	struct luahttpmsg *hp = (struct luahttpmsg *)luaL_checkudata(L, 1, META_HTTP_MSG);
	struct http_message *hm = hp->hm;
	struct mg_str *uri = &hm->uri;
	assert(uri->p && uri->len > 0 && uri->len < 260);
	char *buff = (char *)malloc(uri->len + 1); 	assert(buff);
	strncpy(buff, uri->p, uri->len);
	buff[uri->len] = 0;
	lua_pushfstring(L, "%s", buff);
	free(buff);
	return 1;
}

static int l_query_var(lua_State *L) {
	return http_var_common(L, "query_string");
}

static int l_body_var(lua_State *L) {
	return http_var_common(L, "body");
}

static int l_http_header(lua_State *L) {
	struct luahttpmsg *hp = (struct luahttpmsg *)luaL_checkudata(L, 1, META_HTTP_MSG);
	const char *key = luaL_checkstring(L, 2);
	struct mg_str *s = mg_get_http_header(hp->hm, key);
	if (!s) {
		lua_pushnil(L);
	}
	else {
		char *buff = (char *)malloc(s->len + 1);
		memcpy(buff, s->p, s->len);
		buff[s->len] = 0;
		lua_pushfstring(L, "%s", buff);
		free(buff); 
	}
	
	return 1;
}

static void ev_handler(struct mg_connection *nc, int ev, void *p) {
	struct httpserver *hs = (struct httpserver *)nc->mgr->user_data;
	
	lua_State *L = hs->L; 
	int top = lua_gettop(L);
	
	lua_getfenv(L, 1); 
	lua_rawgeti(L, -1, 1); 
	lua_remove(L, -2); 	
	
	struct luaconn *conn = lua_newuserdata(L, sizeof(struct luaconn));
	conn->p = p;
	conn->nc = nc;

	luaL_getmetatable(L, META_LUA_CONN); 
	lua_setmetatable(L, -2); 			
	
	lua_pushinteger(L, ev); 
	if (lua_pcall(L, 2, 0, 0)) {
		luaL_error(L, "lua_pcall fail %s", lua_tostring(L, 3)); 
	}

	lua_pop(L, lua_gettop(L) - top); 	
}

static int l_create_server(lua_State *L) {
	const char *root = luaL_checkstring(L, 1);
	const char *addr = luaL_checkstring(L, 2);
	if (!lua_isfunction(L, 3))
		luaL_error(L, "param 3 should be ev_handler callback");
	
	struct httpserver *hs = (struct httpserver *)lua_newuserdata(L, sizeof(struct httpserver));
	memset(hs, 0, sizeof(struct httpserver));
	
	hs->L = L;
	mg_mgr_init(&hs->mgr, hs);
	hs->nc = mg_bind(&hs->mgr, addr, ev_handler);
	
	if (!hs->nc) {
		lua_pushnil(L);
		lua_pushfstring(L, "mg_bind %s fail", addr);
		return 2;
	}
	
	mg_set_protocol_http_websocket(hs->nc);
  
	int len = strlen(root);
	if (len >= MAX_ROOT_SIZE)
		len = MAX_ROOT_SIZE - 1;
	strncpy(hs->root, root, len);
	hs->opts.document_root = hs->root;
	
	//hs->opts.enable_directory_listing = "yes";
	//hs->opts.access_log_file = "/tmp/log.txt";
	
	
	luaL_getmetatable(L, META_MONGOOSE);
	lua_setmetatable(L, -2);
	
	lua_createtable(L, 1, 0);
	lua_pushvalue(L, 3);
	lua_rawseti(L, -2, 1);
    lua_setfenv(L, -2);

	return 1;
}


static int l_poll_server(lua_State *L) { 
	struct httpserver *hs = (struct httpserver *)luaL_checkudata(L, 1, META_MONGOOSE);
	int ms = lua_tointeger(L, 2); 
	mg_mgr_poll(&hs->mgr, ms > 0 ? ms : 1000); 
	return 0;
}

static luaL_Reg fns[] = {  
	{ "poll", 	l_poll_server },  
	{ NULL, NULL }
};

static luaL_Reg reg[] = {
	{ "create_server", l_create_server }, 
	{ NULL, NULL }
};

static luaL_Reg conn_fns[] = {
	{ "ip", 			l_ip 			},
	{ "addr", 			l_addr 			},
	{ "send", 			l_send 			},
	{ "send_close", 	l_send_close	},
	{ "serve_http", 	l_serve_http 	},
	{ "http_message", 	l_http_message	}, 
	{ NULL, NULL }
}; 

static luaL_Reg http_msg_func[] = {
	{ "uri", 			l_uri 			},
	{ "query_var", 		l_query_var 	},
	{ "body_var", 		l_body_var 		},
	{ "http_header", 	l_http_header 	},
	{ NULL, NULL }
};

static void create_metatable(lua_State *L, luaL_Reg *reg, const char *mt_name) {
	luaL_newmetatable(L, mt_name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_register(L, NULL, reg);
}

struct constant {
	const char *key;
	int val;
};


static struct constant s_const[] = {
	{"MG_EV_POLL", 			MG_EV_POLL			},
	{"MG_EV_ACCEPT", 		MG_EV_ACCEPT		},
	{"MG_EV_CONNECT", 		MG_EV_CONNECT		},
	{"MG_EV_RECV", 			MG_EV_RECV			},
	{"MG_EV_SEND", 			MG_EV_SEND			},
	{"MG_EV_CLOSE", 		MG_EV_CLOSE			},
	{"MG_EV_HTTP_REQUEST", 	MG_EV_HTTP_REQUEST	},
	{"MG_EV_HTTP_REPLY", 	MG_EV_HTTP_REPLY	},
	{"MG_EV_HTTP_CHUNK", 	MG_EV_HTTP_CHUNK	},
	{"MG_EV_SSI_CALL", 		MG_EV_SSI_CALL		}, 
	{NULL, 					0					}
};
static void register_constant(lua_State *L) {
	int i;
	for (i = 0; s_const[i].key; i++) {
		lua_pushstring(L, s_const[i].key);
		lua_pushinteger(L, s_const[i].val);
		lua_rawset(L, -3);
	}
}

LUALIB_API int luaopen_mongoose(lua_State *L) {
	create_metatable(L, fns, META_MONGOOSE);
	create_metatable(L, conn_fns, META_LUA_CONN);
	create_metatable(L, http_msg_func, META_HTTP_MSG);
	luaL_newlib(L, reg); 
	register_constant(L);	
	return 1;
}
