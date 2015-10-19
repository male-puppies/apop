TARGETS 	:= se.so 
#selua

FLAGS		:= -fPIC -Wall -O2 -g
LDFLAGS		:=

ifneq ($(CHECK_LEAK),)
FLAGS		+= -O0 -fsanitize=leak
LDFLAGS		+= -fsanitize=leak
endif

ifneq ($(CHECK_MEMORY),)
FLAGS		+= -O0 -fsanitize=address
LDFLAGS		+= -fsanitize=address
endif

ifneq ($(USE_LUAJIT),)
FLAGS		+= -I/usr/include/luajit-2.0
LDFLAGS		+= -lluajit-5.1
else
FLAGS		+= -I$(LUA_INC)
LDFLAGS		+= -L$(LUA_INC) -llua
endif

CFLAGS		:= $(FLAGS)

SE_SRC		:= $(wildcard se_*.c) $(wildcard utils/*.c)
SE_OBJS		:= $(SE_SRC:%.c=%.o)
SELUA_OBJS	:= selua.o
OBJECTS 	:= $(SE_OBJS) $(SELUA_OBJS)

.PHONY: all clean

all: $(TARGETS)

clean:
	rm -f $(OBJECTS)
	rm -f $(TARGETS)

se_ev.o: se_ev.c
	$(CC) $(CFLAGS) -w -c -o $@ $^

se.so: $(SE_OBJS)
	$(CC) $(LDFLAGS) -shared -o $@ $^

selua: $(SE_OBJS) $(SELUA_OBJS)
	$(CC) $(LDFLAGS) -o $@ $^
