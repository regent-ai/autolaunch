defmodule Autolaunch.BetaReadiness do
  @moduledoc false

  alias Autolaunch.Launch
  alias Autolaunch.RegentStaking
  alias Autolaunch.Repo

  @base_family_chain_ids [8_453, 84_532]
  @launch_address_checks [
    {:cca_factory_address, "AUTOLAUNCH_CCA_FACTORY_ADDRESS"},
    {:pool_manager_address, "AUTOLAUNCH_UNISWAP_V4_POOL_MANAGER"},
    {:position_manager_address, "AUTOLAUNCH_UNISWAP_V4_POSITION_MANAGER"},
    {:usdc_address, "AUTOLAUNCH_USDC_ADDRESS"},
    {:revenue_share_factory_address, "AUTOLAUNCH_REVENUE_SHARE_FACTORY_ADDRESS"},
    {:revenue_ingress_factory_address, "AUTOLAUNCH_REVENUE_INGRESS_FACTORY_ADDRESS"},
    {:lbp_strategy_factory_address, "AUTOLAUNCH_LBP_STRATEGY_FACTORY_ADDRESS"},
    {:token_factory_address, "AUTOLAUNCH_TOKEN_FACTORY_ADDRESS"},
    {:identity_registry_address, "AUTOLAUNCH_IDENTITY_REGISTRY_ADDRESS"}
  ]
  @expected_routes [
    {:get, "/"},
    {:get, "/health"},
    {:get, "/regent-staking"},
    {:get, "/contracts"},
    {:get, "/v1/app/regent/staking"},
    {:post, "/v1/app/launch/preview"},
    {:get, "/v1/app/auctions"}
  ]

  def run do
    checks =
      [
        repo_check(),
        launch_chain_check(),
        launch_rpc_check()
      ] ++
        launch_address_checks() ++
        [
          regent_staking_config_check(),
          route_exposure_check(),
          launch_read_path_check(),
          regent_staking_read_path_check()
        ]

    %{
      ok: Enum.all?(checks, & &1.ok),
      checks: checks
    }
  end

  defp repo_check do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> ok("database", "Database connection works.")
      {:error, reason} -> fail("database", "Database connection failed: #{inspect(reason)}")
    end
  end

  defp launch_chain_check do
    launch = Application.get_env(:autolaunch, :launch, [])
    chain_id = Keyword.get(launch, :chain_id)

    if chain_id in @base_family_chain_ids do
      ok("launch_chain", "Launch chain is Base family: #{chain_id}.")
    else
      fail("launch_chain", "Launch chain must be Base mainnet or Base Sepolia.")
    end
  end

  defp launch_rpc_check do
    launch = Application.get_env(:autolaunch, :launch, [])

    if present?(Keyword.get(launch, :rpc_url)) do
      ok("launch_rpc", "AUTOLAUNCH_RPC_URL is configured.")
    else
      fail("launch_rpc", "AUTOLAUNCH_RPC_URL is missing.")
    end
  end

  defp launch_address_checks do
    launch = Application.get_env(:autolaunch, :launch, [])

    Enum.map(@launch_address_checks, fn {key, env_name} ->
      if address?(Keyword.get(launch, key)) do
        ok("launch_#{key}", "#{env_name} is configured.")
      else
        fail("launch_#{key}", "#{env_name} is missing or invalid.")
      end
    end)
  end

  defp regent_staking_config_check do
    config = Application.get_env(:autolaunch, :regent_staking, [])

    cond do
      Keyword.get(config, :chain_id) not in @base_family_chain_ids ->
        fail(
          "regent_staking_config",
          "REGENT_STAKING_CHAIN_ID must be Base mainnet or Base Sepolia."
        )

      not present?(Keyword.get(config, :rpc_url)) ->
        fail("regent_staking_config", "REGENT_STAKING_RPC_URL is missing.")

      not address?(Keyword.get(config, :contract_address)) ->
        fail("regent_staking_config", "REGENT_REVENUE_STAKING_ADDRESS is missing or invalid.")

      true ->
        ok("regent_staking_config", "Regent staking configuration is present.")
    end
  end

  defp route_exposure_check do
    live_routes =
      AutolaunchWeb.Router.__routes__()
      |> MapSet.new(fn route -> {route.verb, route.path} end)

    missing = Enum.reject(@expected_routes, &MapSet.member?(live_routes, &1))

    case missing do
      [] -> ok("route_exposure", "Required public routes are present.")
      _ -> fail("route_exposure", "Missing required routes: #{format_routes(missing)}.")
    end
  end

  defp launch_read_path_check do
    case launch_module().list_auctions(%{"mode" => "all", "sort" => "newest"}, nil) do
      auctions when is_list(auctions) ->
        ok(
          "launch_read_path",
          "Autolaunch launch read path returned #{length(auctions)} auctions."
        )

      other ->
        fail("launch_read_path", "Autolaunch launch read path returned #{inspect(other)}.")
    end
  rescue
    error ->
      fail("launch_read_path", "Autolaunch launch read path failed: #{Exception.message(error)}")
  end

  defp regent_staking_read_path_check do
    case regent_staking_module().overview(nil) do
      {:ok, _state} ->
        ok("regent_staking_read_path", "Regent staking read path works.")

      {:error, reason} ->
        fail("regent_staking_read_path", "Regent staking read path failed: #{inspect(reason)}.")

      other ->
        fail("regent_staking_read_path", "Regent staking read path returned #{inspect(other)}.")
    end
  rescue
    error ->
      fail(
        "regent_staking_read_path",
        "Regent staking read path failed: #{Exception.message(error)}"
      )
  end

  defp launch_module do
    :autolaunch
    |> Application.get_env(:beta_readiness, [])
    |> Keyword.get(:launch_module, Launch)
  end

  defp regent_staking_module do
    :autolaunch
    |> Application.get_env(:beta_readiness, [])
    |> Keyword.get(:regent_staking_module, RegentStaking)
  end

  defp format_routes(routes) do
    routes
    |> Enum.map(fn {method, path} ->
      "#{method |> Atom.to_string() |> String.upcase()} #{path}"
    end)
    |> Enum.join(", ")
  end

  defp ok(key, detail), do: %{key: key, ok: true, detail: detail}
  defp fail(key, detail), do: %{key: key, ok: false, detail: detail}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp address?(value) when is_binary(value) do
    Regex.match?(~r/^0x[0-9a-fA-F]{40}$/, String.trim(value))
  end

  defp address?(_value), do: false
end
