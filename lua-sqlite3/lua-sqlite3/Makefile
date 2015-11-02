#all:
#	$(CC) -fpic -shared *.c -o lsqlite3.so -I ../LuaJIT-master/src/ -I ../sqlite3/ -L ../../run/lib/ -llua -lsqlite3
all: 
	$(CC) *.c -fPIC -shared -o lsqlite53.so -I../../lua53/lua-5.3.1/src/ -L$(LUA53_SO_DIR) -llua53 -I../../sqlite3.9/sqlite-autoconf-3090100 -L../../sqlite3.9/sqlite-autoconf-3090100 -lsqlite3  -D BY_LUA_53=1
	$(CC) *.c -fPIC -shared -o lsqlite.so -I$(LUA_INC) -L$(LUA_INC) -llua  -I../../sqlite3.9/sqlite-autoconf-3090100 -L../../sqlite3.9/sqlite-autoconf-3090100 -lsqlite3