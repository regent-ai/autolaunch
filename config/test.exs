import Config

test_database_url =
  System.get_env("LOCAL_DATABASE_URL") ||
    System.get_env("DATABASE_URL") ||
    System.get_env("DATABASE_URL_UNPOOLED")

if is_binary(test_database_url) and String.trim(test_database_url) != "" do
  config :autolaunch, Autolaunch.Repo,
    url: test_database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10
else
  config :autolaunch, Autolaunch.Repo,
    username:
      System.get_env("DB_USER") || System.get_env("PGUSER") || System.get_env("USER") ||
        "postgres",
    password: System.get_env("DB_PASS") || System.get_env("PGPASSWORD") || "",
    hostname: System.get_env("DB_HOST") || System.get_env("PGHOST") || "localhost",
    port: String.to_integer(System.get_env("DB_PORT") || System.get_env("PGPORT") || "5432"),
    database: System.get_env("DB_NAME") || "autolaunch_test",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10
end

config :autolaunch, AutolaunchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base: "0wP3dZNju0aYGiE9XBJoTKcX9P8lWl9OCyD9iGYj2mTq4P7sVjJkJv9s7JvFh9uU",
  server: false

config :autolaunch, :privy,
  app_id: "test-app",
  verification_key: "test-key"

config :autolaunch, :siwa,
  internal_url: "http://localhost:4100",
  shared_secret: "test-secret",
  skip_http_verify: true

config :agent_world, :world_id,
  app_id: "app_test",
  action: "agentbook-registration",
  rp_id: "app_staging_test",
  signing_key: "0x59c6995e998f97a5a0044966f094538c5f6c75a5d9e7f0b6e6a0f9f5d4d17ce4",
  ttl_seconds: 300

config :agent_world, :networks, %{
  "world" => %{rpc_url: "https://world.example", relay_url: nil},
  "base" => %{rpc_url: "https://base.example", relay_url: nil},
  "base-sepolia" => %{rpc_url: "https://base-sepolia.example", relay_url: nil}
}

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
