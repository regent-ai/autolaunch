defmodule Autolaunch.PublisherTest do
  use Autolaunch.DataCase, async: true

  alias Autolaunch.Launch.Job
  alias Autolaunch.Publisher
  alias Autolaunch.Publisher.ChainRevenueSnapshot
  alias Autolaunch.Publisher.EpochRoot
  alias Autolaunch.Publisher.RegentEpoch
  alias Autolaunch.Repo

  defmodule AdapterStub do
    @behaviour Autolaunch.Publisher.Adapter

    @impl true
    def build_epoch_root(job, epoch) do
      {:ok,
       %{
         root: "root:#{job.agent_id}:#{epoch}",
         total_staked: Decimal.new("125000000000000000000"),
         metadata: %{"source" => "stub"}
       }}
    end

    @impl true
    def publish_vault_epoch(_job, _epoch, _payload), do: :ok

    @impl true
    def build_chain_revenue_snapshots(job, epoch) do
      {:ok,
       [
         %{
           agent_id: job.agent_id,
           epoch: epoch,
           chain_id: job.chain_id,
           gross_revenue_usdc: Decimal.new("42.500000"),
           metadata: %{"normalized" => true}
         }
       ]}
    end

    @impl true
    def build_regent_epoch(epoch, _jobs, total_revenue_usdc) do
      {:ok,
       %{
         root: "regent-root:#{epoch}",
         total_revenue_usdc: total_revenue_usdc,
         emission_amount: Decimal.new("10.000000"),
         metadata: %{"published_by" => "stub"}
       }}
    end

    @impl true
    def publish_regent_epoch(_epoch, _payload), do: :ok
  end

  setup do
    previous = Application.get_env(:autolaunch, :publisher, [])

    Application.put_env(:autolaunch, :publisher,
      enabled: false,
      interval_ms: 300_000,
      epoch_seconds: 259_200,
      epoch_genesis_ts: 1_700_000_000,
      adapter: AdapterStub
    )

    on_exit(fn -> Application.put_env(:autolaunch, :publisher, previous) end)
    :ok
  end

  test "run_once persists epoch roots, revenue snapshots, and regent epoch" do
    now = ~U[2026-03-20 00:00:00Z]

    {:ok, _job} =
      %Job{}
      |> Job.create_changeset(%{
        job_id: "job_publish",
        owner_address: "0x1111111111111111111111111111111111111111",
        agent_id: "1:42",
        token_name: "Atlas Coin",
        token_symbol: "ATLAS",
        recovery_safe_address: "0x1111111111111111111111111111111111111111",
        auction_proceeds_recipient: "0x1111111111111111111111111111111111111111",
        ethereum_revenue_treasury: "0x1111111111111111111111111111111111111111",
        base_revenue_treasury: "0x1111111111111111111111111111111111111111",
        tempo_revenue_treasury: "0x1111111111111111111111111111111111111111",
        base_emission_recipient: "0x1111111111111111111111111111111111111111",
        network: "ethereum-mainnet",
        chain_id: 1,
        status: "ready",
        step: "ready",
        total_supply: "1000",
        message: "signed",
        siwa_nonce: "nonce-1",
        siwa_signature: "sig",
        issued_at: now,
        epoch_seconds: 259_200
      })
      |> Repo.insert()

    Repo.get!(Job, "job_publish")
    |> Job.update_changeset(%{
      rights_hub_address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ethereum_vault_address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    })
    |> Repo.update!()

    result = Publisher.run_once(now)

    assert result.ready_jobs == 1

    root = Repo.get_by!(EpochRoot, agent_id: "1:42", epoch: result.epoch, chain_id: 1)
    snapshot =
      Repo.get_by!(ChainRevenueSnapshot, agent_id: "1:42", epoch: result.epoch, chain_id: 1)
    regent_epoch = Repo.get_by!(RegentEpoch, epoch: result.epoch)

    assert root.root == "root:1:42:#{result.epoch}"
    assert Decimal.equal?(snapshot.gross_revenue_usdc, Decimal.new("42.500000"))
    assert Decimal.equal?(regent_epoch.total_revenue_usdc, Decimal.new("42.500000"))
    assert Decimal.equal?(regent_epoch.emission_amount, Decimal.new("10.000000"))
  end
end
