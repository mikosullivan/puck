FROM openresty/openresty:alpine-fat

RUN apk add --no-cache \
    sqlite \
    sqlite-dev \
    build-base \
    openssl \
    openssl-dev

RUN luarocks install lua-resty-openssl && \
    luarocks install lua-resty-http    && \
    luarocks install lsqlite3

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/       /app/lua/

RUN mkdir -p /data

EXPOSE 8080

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]
