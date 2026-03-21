import Config

if System.get_env("PHX_SERVER") do
  config :autolaunch, AutolaunchWeb.Endpoint, server: true
end

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

config :autolaunch, AutolaunchWeb.Endpoint,
  http: [port: String.to_integer(env_or_dotenv.("PORT", "4010"))]

config :autolaunch, :privy,
  app_id: env_or_dotenv.("PRIVY_APP_ID", ""),
  verification_key: env_or_dotenv.("PRIVY_VERIFICATION_KEY", "")

config :autolaunch, :siwa,
  internal_url: env_or_dotenv.("SIWA_INTERNAL_URL", "http://siwa-sidecar:4100"),
  shared_secret: env_or_dotenv.("SIWA_SHARED_SECRET", ""),
  http_connect_timeout_ms:
    String.to_integer(env_or_dotenv.("SIWA_HTTP_CONNECT_TIMEOUT_MS", "2000")),
  http_receive_timeout_ms:
    String.to_integer(env_or_dotenv.("SIWA_HTTP_RECEIVE_TIMEOUT_MS", "5000")),
  skip_http_verify: env_or_dotenv.("SIWA_SKIP_HTTP_VERIFY", "false") in ["1", "true", "TRUE"]

config :autolaunch, :launch,
  chain_id: String.to_integer(env_or_dotenv.("AUTOLAUNCH_CHAIN_ID", "1")),
  allow_unverified_owner:
    env_or_dotenv.("AUTOLAUNCH_ALLOW_UNVERIFIED_OWNER", "false") in ["1", "true", "TRUE"],
  deploy_binary: env_or_dotenv.("AUTOLAUNCH_DEPLOY_BINARY", "forge"),
  deploy_workdir: env_or_dotenv.("AUTOLAUNCH_DEPLOY_WORKDIR", ""),
  deploy_script_target:
    env_or_dotenv.(
      "AUTOLAUNCH_DEPLOY_SCRIPT_TARGET",
      "scripts/ExampleCCADeploymentScript.s.sol:ExampleCCADeploymentScript"
    ),
  deploy_output_marker: env_or_dotenv.("AUTOLAUNCH_DEPLOY_OUTPUT_MARKER", "CCA_RESULT_JSON:"),
  eth_mainnet_rpc_url:
    env_or_dotenv.("ETH_MAINNET_RPC_URL", env_or_dotenv.("ETHEREUM_MAINNET_RPC_URL", "")),
  eth_sepolia_rpc_url:
    env_or_dotenv.("ETH_SEPOLIA_RPC_URL", env_or_dotenv.("ETHEREUM_SEPOLIA_RPC_URL", "")),
  eth_mainnet_factory_address:
    env_or_dotenv.(
      "ETH_MAINNET_FACTORY_ADDRESS",
      env_or_dotenv.(
        "ETHEREUM_MAINNET_FACTORY_ADDRESS",
        "0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5"
      )
    ),
  eth_sepolia_factory_address:
    env_or_dotenv.(
      "ETH_SEPOLIA_FACTORY_ADDRESS",
      env_or_dotenv.(
        "ETHEREUM_SEPOLIA_FACTORY_ADDRESS",
        "0xCCccCcCAE7503Cac057829BF2811De42E16e0bD5"
      )
    ),
  eth_mainnet_pool_manager_address:
    env_or_dotenv.(
      "ETH_MAINNET_UNISWAP_V4_POOL_MANAGER",
      env_or_dotenv.("ETHEREUM_MAINNET_UNISWAP_V4_POOL_MANAGER", "")
    ),
  eth_sepolia_pool_manager_address:
    env_or_dotenv.(
      "ETH_SEPOLIA_UNISWAP_V4_POOL_MANAGER",
      env_or_dotenv.("ETHEREUM_SEPOLIA_UNISWAP_V4_POOL_MANAGER", "")
    ),
  eth_mainnet_usdc_address:
    env_or_dotenv.("ETH_MAINNET_USDC_ADDRESS", env_or_dotenv.("ETHEREUM_USDC_ADDRESS", "")),
  eth_sepolia_usdc_address:
    env_or_dotenv.("ETH_SEPOLIA_USDC_ADDRESS", env_or_dotenv.("ETHEREUM_SEPOLIA_USDC_ADDRESS", "")),
  erc8004_mainnet_subgraph_url:
    env_or_dotenv.(
      "ERC8004_MAINNET_SUBGRAPH_URL",
      env_or_dotenv.("ETH_MAINNET_ERC8004_SUBGRAPH_URL", "")
    ),
  erc8004_sepolia_subgraph_url:
    env_or_dotenv.(
      "ERC8004_SEPOLIA_SUBGRAPH_URL",
      env_or_dotenv.("ETH_SEPOLIA_ERC8004_SUBGRAPH_URL", "")
    ),
  regent_multisig_address:
    env_or_dotenv.("REGENT_MULTISIG_ADDRESS", "0x9fa152B0EAdbFe9A7c5C0a8e1D11784f22669a3e"),
  regent_emissions_distributor_address:
    env_or_dotenv.("REGENT_EMISSIONS_DISTRIBUTOR_ADDRESS", ""),
  deploy_account: env_or_dotenv.("AUTOLAUNCH_DEPLOY_ACCOUNT", ""),
  deploy_password: env_or_dotenv.("AUTOLAUNCH_DEPLOY_PASSWORD", ""),
  deploy_private_key: env_or_dotenv.("AUTOLAUNCH_DEPLOY_PRIVATE_KEY", ""),
  mock_deploy:
    env_or_dotenv.("AUTOLAUNCH_MOCK_DEPLOY", "false") in [
      "1",
      "true",
      "TRUE"
    ]

config :autolaunch, :publisher,
  enabled: env_or_dotenv.("AUTOLAUNCH_PUBLISHER_ENABLED", "false") in ["1", "true", "TRUE"],
  interval_ms: String.to_integer(env_or_dotenv.("AUTOLAUNCH_PUBLISHER_INTERVAL_MS", "300000")),
  epoch_seconds: String.to_integer(env_or_dotenv.("AUTOLAUNCH_EPOCH_SECONDS", "259200")),
  epoch_genesis_ts:
    String.to_integer(env_or_dotenv.("AUTOLAUNCH_EPOCH_GENESIS_TS", "1700000000"))

config :agent_world, :world_id,
  app_id: env_or_dotenv.("WORLD_ID_APP_ID", ""),
  action: env_or_dotenv.("WORLD_ID_ACTION", "agentbook-registration"),
  rp_id: env_or_dotenv.("WORLD_ID_RP_ID", ""),
  signing_key: env_or_dotenv.("WORLD_ID_SIGNING_KEY", ""),
  ttl_seconds: String.to_integer(env_or_dotenv.("WORLD_ID_TTL_SECONDS", "300"))

config :agent_world, :networks, %{
  "world" => %{
    rpc_url: env_or_dotenv.("WORLDCHAIN_RPC_URL", env_or_dotenv.("WORLD_RPC_URL", "")),
    contract_address:
      env_or_dotenv.(
        "WORLDCHAIN_AGENTBOOK_ADDRESS",
        env_or_dotenv.("WORLD_AGENTBOOK_ADDRESS", "0xA23aB2712eA7BBa896930544C7d6636a96b944dA")
      ),
    relay_url: env_or_dotenv.("WORLDCHAIN_AGENTBOOK_RELAY_URL", "")
  },
  "base" => %{
    rpc_url: env_or_dotenv.("BASE_MAINNET_RPC_URL", env_or_dotenv.("BASE_RPC_URL", "")),
    contract_address:
      env_or_dotenv.("BASE_AGENTBOOK_ADDRESS", "0xE1D1D3526A6FAa37eb36bD10B933C1b77f4561a4"),
    relay_url: env_or_dotenv.("BASE_AGENTBOOK_RELAY_URL", "")
  },
  "base-sepolia" => %{
    rpc_url: env_or_dotenv.("BASE_SEPOLIA_RPC_URL", ""),
    contract_address:
      env_or_dotenv.(
        "BASE_SEPOLIA_AGENTBOOK_ADDRESS",
        "0xA23aB2712eA7BBa896930544C7d6636a96b944dA"
      ),
    relay_url: env_or_dotenv.("BASE_SEPOLIA_AGENTBOOK_RELAY_URL", "")
  }
}

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      """

  host = System.get_env("PHX_HOST") || "autolaunch.sh"

  config :autolaunch, Autolaunch.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :autolaunch, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :autolaunch, AutolaunchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
