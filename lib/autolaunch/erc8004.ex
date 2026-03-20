defmodule Autolaunch.ERC8004 do
  @moduledoc false

  @default_subgraph_urls %{
    1 =>
      "https://gateway.thegraph.com/api/7fd2e7d89ce3ef24cd0d4590298f0b2c/subgraphs/id/FV6RR6y13rsnCxBAicKuQEwDp8ioEGiNaWaZUmvr1F8k",
    11_155_111 =>
      "https://gateway.thegraph.com/api/00a452ad3cd1900273ea62c1bf283f93/subgraphs/id/6wQRC7geo9XYAhckfmfo8kbMRLeWU8KQd3XsJqFKmZLT"
  }

  @identity_registries %{
    1 => "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
    11_155_111 => "0x8004A818BFB912233c491871b3d84c89A494BD9e"
  }

  @agent_query """
  query Agents($where: Agent_filter, $first: Int!) {
    agents(where: $where, first: $first, orderBy: updatedAt, orderDirection: desc) {
      id
      chainId
      agentId
      owner
      operators
      agentWallet
      agentURI
      registrationFile {
        id
        name
        description
        image
        active
        ens
        webEndpoint
      }
    }
  }
  """

  @max_results 100

  def list_accessible_identities(wallet_addresses, chain_ids \\ [1, 11_155_111]) do
    wallets =
      wallet_addresses
      |> Enum.map(&normalize_address/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if wallets == [] do
      []
    else
      chain_ids
      |> Enum.flat_map(&fetch_chain_identities(&1, wallets))
      |> Enum.reduce(%{}, &merge_identity/2)
      |> Map.values()
      |> Enum.sort_by(&sort_tuple/1)
    end
  end

  def identity_registry(chain_id), do: Map.get(@identity_registries, chain_id)

  defp fetch_chain_identities(chain_id, wallets) do
    owned =
      query_agents(chain_id, %{"owner_in" => wallets})
      |> Enum.map(&decorate_identity(&1, chain_id, wallets, "owner"))

    operated =
      wallets
      |> Enum.flat_map(fn wallet ->
        query_agents(chain_id, %{"operators_contains" => [wallet]})
        |> Enum.map(&decorate_identity(&1, chain_id, wallets, "operator"))
      end)

    wallet_bound =
      wallets
      |> Enum.flat_map(fn wallet ->
        query_agents(chain_id, %{"agentWallet" => wallet})
        |> Enum.map(&decorate_identity(&1, chain_id, wallets, "wallet_bound"))
      end)

    owned ++ operated ++ wallet_bound
  end

  defp query_agents(chain_id, where) do
    with {:ok, url} <- subgraph_url(chain_id),
         {:ok, response} <-
           Req.post(url,
             json: %{
               "query" => @agent_query,
               "variables" => %{"where" => where, "first" => @max_results}
             }
           ),
         %{"data" => %{"agents" => agents}} when is_list(agents) <- response.body do
      agents
    else
      _ -> []
    end
  end

  defp subgraph_url(chain_id) do
    launch_config = Application.get_env(:autolaunch, :launch, [])

    value =
      case chain_id do
        1 -> Keyword.get(launch_config, :erc8004_mainnet_subgraph_url)
        11_155_111 -> Keyword.get(launch_config, :erc8004_sepolia_subgraph_url)
        _ -> nil
      end

    case value do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:ok, Map.fetch!(@default_subgraph_urls, chain_id)}
    end
  end

  defp decorate_identity(agent, chain_id, wallets, access_mode) do
    registration = Map.get(agent, "registrationFile") || %{}
    owner = normalize_address(Map.get(agent, "owner"))
    operators = Enum.map(Map.get(agent, "operators", []), &normalize_address/1)
    agent_wallet = normalize_address(Map.get(agent, "agentWallet"))
    token_id = to_string(Map.get(agent, "agentId"))
    agent_id = "#{chain_id}:#{token_id}"

    %{
      id: agent_id,
      agent_id: agent_id,
      chain_id: chain_id,
      token_id: token_id,
      registry_address: identity_registry(chain_id),
      owner_address: owner,
      operator_addresses: operators,
      agent_wallet: agent_wallet,
      access_mode: infer_access_mode(access_mode, owner, operators, agent_wallet, wallets),
      name: Map.get(registration, "name") || "ERC-8004 Agent ##{token_id}",
      description: Map.get(registration, "description"),
      image_url: Map.get(registration, "image"),
      ens: Map.get(registration, "ens"),
      agent_uri: Map.get(agent, "agentURI"),
      web_endpoint: Map.get(registration, "webEndpoint"),
      active: truthy?(Map.get(registration, "active")),
      source: "erc8004"
    }
  end

  defp infer_access_mode("owner", owner, _operators, _agent_wallet, wallets) do
    if owner in wallets, do: "owner", else: "wallet_bound"
  end

  defp infer_access_mode(_access_mode, _owner, operators, _agent_wallet, wallets) do
    cond do
      Enum.any?(operators, &(&1 in wallets)) -> "operator"
      true -> "wallet_bound"
    end
  end

  defp merge_identity(identity, acc) do
    Map.update(acc, identity.agent_id, identity, fn existing ->
      if access_rank(identity.access_mode) < access_rank(existing.access_mode),
        do: identity,
        else: existing
    end)
  end

  defp access_rank("owner"), do: 0
  defp access_rank("operator"), do: 1
  defp access_rank("wallet_bound"), do: 2
  defp access_rank(_), do: 3

  defp sort_tuple(identity) do
    {access_rank(identity.access_mode), String.downcase(identity.name), identity.agent_id}
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp normalize_address(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.downcase(trimmed)
    end
  end

  defp normalize_address(_value), do: nil
end
