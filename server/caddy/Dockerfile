# A Caddy image with the rate-limit handler compiled in. Stock Caddy has automatic TLS and WebSocket
# proxying built in, but NOT rate limiting — that lives in a community module, so we build a custom
# binary with xcaddy and ship just that binary on the official runtime image.
FROM caddy:2-builder AS build
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2
COPY --from=build /usr/bin/caddy /usr/bin/caddy
