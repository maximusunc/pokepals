# Seed data for local development. Idempotent — run repeatedly:
#
#     mix run priv/repo/seeds.exs
#
# In a packaged release (Docker/prod, no Mix) the same seeds run via:
#
#     bin/server eval 'Server.Release.seed()'
#
# The actual logic lives in Server.Seeds so both paths share it. The seed WORLDS are essential
# bootstrap content — the client can't enter a world that isn't in the catalog.

IO.puts(Server.Seeds.run())
