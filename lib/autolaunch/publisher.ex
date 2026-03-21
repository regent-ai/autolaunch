defmodule Autolaunch.Publisher do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Autolaunch.Launch.Job
  alias Autolaunch.Publisher.ChainRevenueSnapshot
  alias Autolaunch.Publisher.EpochRoot
  alias Autolaunch.Publisher.RegentEpoch
  alias Autolaunch.Repo

  def enabled? do
    publisher_config()
    |> Keyword.get(:enabled, false)
  end

  def run_once(now \\ DateTime.utc_now()) do
    epoch = epoch_for(now)
    jobs = ready_jobs()

    root_results =
      Enum.map(jobs, fn job ->
        publish_agent_epoch(job, epoch)
      end)

    total_revenue_usdc =
      Repo.one(
        from snapshot in ChainRevenueSnapshot,
          where: snapshot.epoch == ^epoch,
          select: sum(snapshot.gross_revenue_usdc)
      ) || Decimal.new(0)

    regent_result = publish_regent_epoch(epoch, jobs, total_revenue_usdc)

    %{
      epoch: epoch,
      ready_jobs: length(jobs),
      root_results: root_results,
      regent_result: regent_result
    }
  end

  def epoch_for(%DateTime{} = now) do
    genesis_ts = Keyword.get(publisher_config(), :epoch_genesis_ts, 1_700_000_000)
    epoch_seconds = Keyword.get(publisher_config(), :epoch_seconds, 259_200)
    unix_now = DateTime.to_unix(now)

    if unix_now <= genesis_ts do
      1
    else
      div(unix_now - genesis_ts, epoch_seconds) + 1
    end
  end

  defp publish_agent_epoch(job, epoch) do
    case Repo.get_by(EpochRoot, agent_id: job.agent_id, epoch: epoch, chain_id: job.chain_id) do
      %EpochRoot{} = existing ->
        {:ok, existing}

      nil ->
        with {:ok, root_payload} <- adapter().build_epoch_root(job, epoch),
             {:ok, record} <- upsert_epoch_root(job, epoch, root_payload),
             :ok <- adapter().publish_vault_epoch(job, epoch, root_payload),
             {:ok, _snapshots} <- upsert_revenue_snapshots(job, epoch) do
          {:ok, record}
        end
    end
  end

  defp publish_regent_epoch(epoch, jobs, total_revenue_usdc) do
    case Repo.get_by(RegentEpoch, epoch: epoch) do
      %RegentEpoch{} = existing ->
        {:ok, existing}

      nil ->
        with {:ok, payload} <- adapter().build_regent_epoch(epoch, jobs, total_revenue_usdc),
             attrs <- %{
               epoch: epoch,
               total_revenue_usdc: normalize_decimal(payload.total_revenue_usdc),
               emission_amount: normalize_decimal(payload.emission_amount),
               root: payload.root,
               published_at: DateTime.utc_now(),
               metadata: Map.get(payload, :metadata, %{})
             },
             {:ok, record} <-
               %RegentEpoch{}
               |> RegentEpoch.changeset(attrs)
               |> Repo.insert(
                 on_conflict: [set: Keyword.drop(Map.to_list(attrs), [:epoch])],
                 conflict_target: [:epoch]
               ),
             :ok <- adapter().publish_regent_epoch(epoch, payload) do
          {:ok, record}
        end
    end
  end

  defp upsert_epoch_root(job, epoch, payload) do
    attrs = %{
      agent_id: job.agent_id,
      epoch: epoch,
      chain_id: job.chain_id,
      rights_hub_address: job.rights_hub_address,
      revenue_vault_address: job.ethereum_vault_address,
      root: payload.root,
      total_staked: normalize_decimal(payload.total_staked),
      published_at: DateTime.utc_now(),
      metadata: Map.get(payload, :metadata, %{})
    }

    %EpochRoot{}
    |> EpochRoot.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: Keyword.drop(Map.to_list(attrs), [:agent_id, :epoch, :chain_id])],
      conflict_target: [:agent_id, :epoch, :chain_id]
    )
  end

  defp upsert_revenue_snapshots(job, epoch) do
    with {:ok, snapshots} <- adapter().build_chain_revenue_snapshots(job, epoch) do
      records =
        Enum.map(snapshots, fn snapshot ->
          attrs = %{
            agent_id: job.agent_id,
            epoch: epoch,
            chain_id: Map.get(snapshot, :chain_id) || Map.get(snapshot, "chain_id") || job.chain_id,
            gross_revenue_usdc:
              normalize_decimal(
                Map.get(snapshot, :gross_revenue_usdc) || Map.get(snapshot, "gross_revenue_usdc") ||
                  0
              ),
            metadata: Map.get(snapshot, :metadata) || Map.get(snapshot, "metadata") || %{}
          }

          %ChainRevenueSnapshot{}
          |> ChainRevenueSnapshot.changeset(attrs)
          |> Repo.insert(
            on_conflict: [set: [gross_revenue_usdc: attrs.gross_revenue_usdc, metadata: attrs.metadata]],
            conflict_target: [:agent_id, :epoch, :chain_id]
          )
        end)

      {:ok, records}
    end
  end

  defp ready_jobs do
    Repo.all(
      from job in Job,
        where:
          job.status == "ready" and not is_nil(job.rights_hub_address) and
            not is_nil(job.ethereum_vault_address)
    )
  end

  defp normalize_decimal(%Decimal{} = value), do: value
  defp normalize_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp normalize_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp normalize_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp normalize_decimal(_value), do: Decimal.new(0)

  defp adapter do
    publisher_config()
    |> Keyword.get(:adapter, Autolaunch.Publisher.NoopAdapter)
  end

  defp publisher_config do
    Application.get_env(:autolaunch, :publisher, [])
  end
end
