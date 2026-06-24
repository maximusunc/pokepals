# syntax=docker/dockerfile:1
#
# Two-stage build: compile a self-contained OTP release, then ship only that release on a slim
# base. The result needs no Elixir/Erlang on the host — just Docker. See DEPLOYMENT.md.
#
# The image tags below pin Elixir/Erlang/Debian for a reproducible build. Bump them freely from the
# list at https://hub.docker.com/r/hexpm/elixir/tags — but keep the builder's Debian release (here:
# trixie) in sync with the runtime stage's base image below, so their libc/OpenSSL/ncurses ABIs match.

# ---- Build stage --------------------------------------------------------------------------
FROM hexpm/elixir:1.17.3-erlang-27.3.4-debian-trixie-20260610-slim AS build

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Hex + Rebar, for fetching and compiling dependencies.
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Dependencies first, so this layer is cached unless mix.exs changes.
# (No mix.lock is committed yet; `mix deps.get` resolves it here. Commit server/mix.lock after a
# local `mix deps.get` for fully reproducible builds.)
COPY mix.exs ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Application sources, then build the release. priv/ carries the Ecto migrations into the release.
COPY config config
COPY priv priv
COPY lib lib
RUN mix compile
RUN mix release

# ---- Runtime stage ------------------------------------------------------------------------
# Match the builder's Debian release (trixie) so the BEAM's runtime libs line up.
FROM debian:trixie-slim AS app

# Runtime libs the BEAM needs, plus curl for the healthcheck, plus a UTF-8 locale.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Never run the server as root.
RUN useradd --create-home --shell /bin/bash app
WORKDIR /home/app

COPY --from=build --chown=app:app /app/_build/prod/rel/server ./server

USER app

ENV PORT=4000
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS "http://localhost:${PORT}/health" || exit 1

# Apply DB migrations, then run the server in the foreground. `eval` is a short-lived node that
# runs the migration and exits; `&&` aborts the boot if it fails; `exec` makes the BEAM PID 1 for
# clean signal handling. Needs DATABASE_URL in the environment (compose provides it).
CMD ["/bin/sh", "-c", "/home/app/server/bin/server eval 'Server.Release.migrate()' && exec /home/app/server/bin/server start"]
