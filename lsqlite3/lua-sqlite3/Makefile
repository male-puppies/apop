SQLITE3_FLAGS=-I../../sqlite3.9/sqlite-autoconf-3090100 -L../../sqlite3.9/sqlite-autoconf-3090100 -lsqlite3
all: 
	#$(CC) *.c -fPIC -shared -o lsqlite53.so -I../../lua53/lua-5.3.1/src/ -L$(LUA53_SO_DIR) -llua53 $(SQLITE3_FLAGS) -D BY_LUA_53=1
	$(CC) *.c -fPIC -shared -o lsqlite.so -I$(LUA_INC) -L$(LUA_INC) -llua $(SQLITE3_FLAGS)
clean:
	$(RM) -f *.so 