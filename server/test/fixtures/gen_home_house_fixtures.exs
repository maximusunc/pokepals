# Writes the client's house test fixtures (gates-of-elyra/tests/world_fixtures/home_house_*.json) with the real
# Server.HomeWorld, for a home that has found EVERY world's secret and whose companion has chosen 7 keepsakes:
# so the house's display plinths are all taken and its curio shelves are full, the way a long-time player's is.
#   cd server && mix run --no-start test/fixtures/gen_home_house_fixtures.exs
seeds = Path.wildcard("priv/world_seeds/*.json")

cards =
  for f <- Enum.sort(seeds),
      s = Jason.decode!(File.read!(f))["secret"],
      s != nil do
    {s["id"], %{"qualities" => s["qualities"] || [], "keepsake" => s["keepsake"], "together" => false}}
  end

keepsakes = cards |> Enum.take(7) |> Enum.map(&elem(&1, 0))
now = Server.House.now()

for {name, started} <- [{"home_house_building", now - 60_000}, {"home_house_built", now - 3_600_000}] do
  core =
    Server.HomeWorld.build_core(Server.HomeWorld.template(), %{
      spots: 7,
      keepsakes: keepsakes,
      cards: cards,
      owner_id: "owner-under-test",
      owner_name: "Tester",
      tank: [],
      house: %{"started_at" => started},
      now: now
    })

  File.write!("../gates-of-elyra/tests/world_fixtures/#{name}.json", Jason.encode!(core, pretty: true))
  IO.puts("#{name}: #{length(cards)} finds, #{length(keepsakes)} keepsakes")
end
