
default:	build

clean:
	rm -rf Makefile objs

build:
	$(MAKE) -f objs/Makefile
	$(MAKE) -f objs/Makefile manpage

install:
	$(MAKE) -f objs/Makefile install

upgrade:
	/usr/sbin//sbin/nginx -t

	kill -USR2 `cat /tmp/nginx/nginx.pid`
	sleep 1
	test -f /tmp/nginx/nginx.pid.oldbin

	kill -QUIT `cat /tmp/nginx/nginx.pid.oldbin`
