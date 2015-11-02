SQLITE_SO=libsqlite3.so
SQLITE_BIN=sqlite3
all:$(SQLITE_SO) $(SQLITE_BIN)

$(SQLITE_SO):
	$(CC) -fpic -shared -O2 sqlite3.c -o $(SQLITE_SO) 
	$(STRIP) $(SQLITE_SO) 
$(SQLITE_BIN):$(SQLITE_SO)
	$(CC) shell.c -o $(SQLITE_BIN) -I. -L. -lsqlite3
	$(STRIP) $(SQLITE_BIN) 
clean:
	$(RM) -f $(SQLITE_SO) $(SQLITE_BIN)