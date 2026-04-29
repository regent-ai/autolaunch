defmodule AutolaunchWeb.OperatorStatus do
  @moduledoc false

  alias Autolaunch.InfrastructureConfig
  alias Autolaunch.Repo
  alias Autolaunch.Siwa.Config, as: SiwaConfig

  def snapshot do
    checks = [
      repo_check(),
      cache_check(),
      siwa_check(),
      launch_config_check(),
      regent_config_check(),
      xmtp_config_check()
    ]

    %{
      ok: Enum.all?(checks, &(&1.state == :ready)),
      checked_at: DateTime.utc_now(),
      checks: checks
    }
  end

  defp repo_check do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> check(:ready, "Database", "Reads and writes are available.")
      {:error, _reason} -> check(:blocked, "Database", "Database is not accepting queries.")
    end
  end

  defp cache_check do
    case Autolaunch.LocalCache.status() do
      :ready -> check(:ready, "Local cache", "Hot read cache is ready.")
      {:error, _reason} -> check(:blocked, "Local cache", "Cache is not ready.")
    end
  end

  defp siwa_check do
    case SiwaConfig.fetch_http_config() do
      {:ok, %{internal_url: _url}} -> check(:ready, "Agent sign-in", "Agent auth is configured.")
      {:error, _reason} -> check(:blocked, "Agent sign-in", "Agent auth needs configuration.")
    end
  end

  defp launch_config_check do
    missing =
      case InfrastructureConfig.launch_chain_id() do
        {:ok, _chain_id} -> InfrastructureConfig.launch_missing_address_keys()
        {:error, _reason} -> [:chain_id | InfrastructureConfig.launch_missing_address_keys()]
      end

    if missing == [] do
      check(:ready, "Launch stack", "Base launch addresses are configured.")
    else
      check(:blocked, "Launch stack", "#{length(missing)} launch settings need values.")
    end
  end

  defp regent_config_check do
    if InfrastructureConfig.configured_address?(
         InfrastructureConfig.regent_staking_value(:contract_address)
       ) and
         match?({:ok, _url}, InfrastructureConfig.regent_staking_rpc_url()) do
      check(:ready, "Regent staking", "Regent staking reads are configured.")
    else
      check(:muted, "Regent staking", "Regent staking is not fully configured here.")
    end
  end

  defp xmtp_config_check do
    rooms =
      :autolaunch
      |> Application.get_env(Autolaunch.Xmtp, [])
      |> Keyword.get(:rooms, [])

    if is_list(rooms) and rooms != [] do
      check(:ready, "XMTP rooms", "#{length(rooms)} room setup is configured.")
    else
      check(:blocked, "XMTP rooms", "No XMTP room setup is configured.")
    end
  end

  defp check(state, label, detail), do: %{state: state, label: label, detail: detail}
end
