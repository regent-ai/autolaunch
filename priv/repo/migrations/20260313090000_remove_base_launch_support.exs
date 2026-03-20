defmodule Autolaunch.Repo.Migrations.RemoveBaseLaunchSupport do
  use Ecto.Migration

  def up do
    execute("DELETE FROM autolaunch_bids WHERE chain_id NOT IN (1, 11155111)")

    execute("DELETE FROM autolaunch_auctions WHERE chain_id NOT IN (1, 11155111)")

    execute("DELETE FROM autolaunch_jobs WHERE chain_id NOT IN (1, 11155111)")

    alter table(:autolaunch_jobs) do
      modify :network, :string, null: false, default: "ethereum-mainnet"
      modify :chain_id, :integer, null: false, default: 1
    end

    alter table(:autolaunch_auctions) do
      modify :network, :string, null: false, default: "ethereum-mainnet"
      modify :chain_id, :integer, null: false, default: 1
    end

    alter table(:autolaunch_bids) do
      modify :chain_id, :integer, null: false, default: 1
    end

    create constraint(:autolaunch_jobs, :autolaunch_jobs_chain_id_ethereum_only,
             check: "chain_id IN (1, 11155111)"
           )

    create constraint(:autolaunch_jobs, :autolaunch_jobs_network_ethereum_only,
             check: "network IN ('ethereum-mainnet', 'ethereum-sepolia')"
           )

    create constraint(:autolaunch_auctions, :autolaunch_auctions_chain_id_ethereum_only,
             check: "chain_id IN (1, 11155111)"
           )

    create constraint(:autolaunch_auctions, :autolaunch_auctions_network_ethereum_only,
             check: "network IN ('ethereum-mainnet', 'ethereum-sepolia')"
           )

    create constraint(:autolaunch_bids, :autolaunch_bids_chain_id_ethereum_only,
             check: "chain_id IN (1, 11155111)"
           )

    create constraint(:autolaunch_bids, :autolaunch_bids_network_ethereum_only,
             check: "network IN ('ethereum-mainnet', 'ethereum-sepolia')"
           )
  end

  def down do
    drop constraint(:autolaunch_bids, :autolaunch_bids_network_ethereum_only)
    drop constraint(:autolaunch_bids, :autolaunch_bids_chain_id_ethereum_only)
    drop constraint(:autolaunch_auctions, :autolaunch_auctions_network_ethereum_only)
    drop constraint(:autolaunch_auctions, :autolaunch_auctions_chain_id_ethereum_only)
    drop constraint(:autolaunch_jobs, :autolaunch_jobs_network_ethereum_only)
    drop constraint(:autolaunch_jobs, :autolaunch_jobs_chain_id_ethereum_only)

    alter table(:autolaunch_jobs) do
      modify :network, :string, null: false, default: "ethereum-mainnet"
      modify :chain_id, :integer, null: false, default: 1
    end

    alter table(:autolaunch_auctions) do
      modify :network, :string, null: false, default: "ethereum-mainnet"
      modify :chain_id, :integer, null: false, default: 1
    end

    alter table(:autolaunch_bids) do
      modify :chain_id, :integer, null: false, default: 1
    end
  end
end
