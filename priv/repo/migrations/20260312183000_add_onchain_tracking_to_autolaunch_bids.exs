defmodule Autolaunch.Repo.Migrations.AddOnchainTrackingToAutolaunchBids do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_bids) do
      add :chain_id, :integer, null: false, default: 1
      add :onchain_bid_id, :string
      add :submit_tx_hash, :string
      add :submit_block_number, :integer
      add :exit_tx_hash, :string
      add :claim_tx_hash, :string
    end

    create index(:autolaunch_bids, [:chain_id])

    create unique_index(:autolaunch_bids, [:auction_id, :onchain_bid_id],
             name: :autolaunch_bids_auction_onchain_bid_unique
           )
  end
end
