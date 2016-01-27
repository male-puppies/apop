all: 
	$(CC) -O2 -fPIC -shared *.c -o encrypt.so -I$(LUA_INC) -L$(LUA_INC) -llua
clean:
	$(RM) *so 