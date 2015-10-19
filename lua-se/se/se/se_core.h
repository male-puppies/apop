#pragma once

#include "se.h"

int l_se_run(lua_State *L);
int l_se_go(lua_State *L);
int l_se_time(lua_State *L);
int l_se_sleep(lua_State *L);
int l_se_close(lua_State *L);
int l_se_read(lua_State *L);
int l_se_write(lua_State *L);
int l_se_connect(lua_State *L);
int l_se_listen(lua_State *L);
int l_se_accept(lua_State *L);
int l_se_shutdown(lua_State *L);
int l_se_getsockname(lua_State *L);
int l_se_getpeername(lua_State *L);