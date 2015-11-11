#!/bin/sh
luadir=$1
#LUA_LIB=../lua-5.1.5/src/ LUA_INC=../lua-5.1.5/src/ ./configure --prefix=/home/yjs/lua/run/ \
LUA_LIB=$luadir LUA_INC=$luadir ./configure \
--without-http_charset_module \
--without-http_gzip_module \
--without-http_ssi_module \
--without-http_userid_module \
--without-http_access_module \
--without-http_auth_basic_module \
--without-http_autoindex_module \
--without-http_geo_module \
--without-http_map_module \
--without-http_split_clients_module \
--without-http_referer_module \
--without-http_fastcgi_module \
--without-http_uwsgi_module \
--without-http_scgi_module \
--without-http_memcached_module \
--without-http_limit_conn_module \
--without-http_limit_req_module \
--without-http_empty_gif_module \
--without-http_browser_module \
--without-mail_pop3_module \
--without-mail_imap_module \
--without-mail_smtp_module \
--with-ld-opt="-Wl,-rpath,$luadir" \
--add-module=../ngx_devel_kit-0.2.19 \
--add-module=../lua-nginx-module/ \
--conf-path=/etc/config/nginx.conf \
--prefix=/usr/sbin/ \
--pid-path=/tmp/nginx/nginx.pid \
--error-log-path=/tmp/nginx/error.log