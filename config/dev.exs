import Config

dotenv_values =
  Path.expand("../.env", __DIR__)
  |> File.read()
  |> case do
    {:ok, contents} ->
      contents
      |> String.split("\n")
      |> Enum.reduce(%{}, fn line, acc ->
        trimmed = String.trim(line)

        cond do
          trimmed == "" or String.starts_with?(trimmed, "#") ->
            acc

          true ->
            case String.split(trimmed, "=", parts: 2) do
              [key, value] ->
                normalized =
                  value
                  |> String.trim()
                  |> String.trim_leading("\"")
                  |> String.trim_trailing("\"")
                  |> String.trim_leading("'")
                  |> String.trim_trailing("'")

                Map.put(acc, String.trim(key), normalized)

              _ ->
                acc
            end
        end
      end)

    _ ->
      %{}
  end

env_or_dotenv = fn key, default ->
  System.get_env(key) || Map.get(dotenv_values, key, default)
end

database_url = env_or_dotenv.("LOCAL_DATABASE_URL", env_or_dotenv.("DATABASE_URL", ""))

if is_binary(database_url) and String.trim(database_url) != "" do
  config :autolaunch, Autolaunch.Repo,
    url: database_url,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
else
  config :autolaunch, Autolaunch.Repo,
    username:
      env_or_dotenv.("DB_USER", env_or_dotenv.("PGUSER", System.get_env("USER") || "postgres")),
    password: env_or_dotenv.("DB_PASS", env_or_dotenv.("PGPASSWORD", "")),
    hostname: env_or_dotenv.("DB_HOST", env_or_dotenv.("PGHOST", "localhost")),
    port: String.to_integer(env_or_dotenv.("DB_PORT", env_or_dotenv.("PGPORT", "5432"))),
    database: env_or_dotenv.("DB_NAME", "autolaunch_dev"),
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10
end

config :autolaunch, AutolaunchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(env_or_dotenv.("PORT", "4010"))],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "w9CoAZ94M4ppYt4s7hjMNiVqTNorV6gX2cA8QiAUvM9OuJv6tfX7j5O5F2NiCp3Z",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:autolaunch, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:autolaunch, ~w(--watch)]}
  ]

config :autolaunch, AutolaunchWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/autolaunch_web/router\.ex$"E,
      ~r"lib/autolaunch_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :autolaunch, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
