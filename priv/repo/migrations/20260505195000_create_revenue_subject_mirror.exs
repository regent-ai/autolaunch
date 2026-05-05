defmodule Autolaunch.Repo.Migrations.CreateRevenueSubjectMirror do
  use Ecto.Migration

  def change do
    create table(:autolaunch_revenue_subjects, primary_key: false) do
      add :subject_id, :string, primary_key: true
      add :chain_id, :integer, null: false
      add :subject_kind, :string, null: false
      add :splitter_kind, :string, null: false
      add :token_address, :string, null: false
      add :splitter_address, :string, null: false
      add :ingress_address, :string
      add :treasury_address, :string, null: false
      add :factory_address, :string
      add :creator_address, :string
      add :permissionless, :boolean, null: false, default: false
      add :staker_pool_bps, :integer
      add :protocol_skim_bps_snapshot, :integer
      add :current_protocol_skim_bps, :integer
      add :protocol_fee_usdc_total_raw, :string
      add :regent_emission_total_raw, :string
      add :regent_buyback_total_raw, :string
      add :oracle_kind, :string
      add :regent_weth_pool_id, :string
      add :team_shared_status, :string, null: false, default: "unverified"
      add :vesting_wallet_address, :string
      add :created_tx_hash, :string
      add :created_block_number, :integer
      add :created_log_index, :integer

      timestamps()
    end

    create index(:autolaunch_revenue_subjects, [:chain_id, :token_address])
    create index(:autolaunch_revenue_subjects, [:subject_kind])
    create index(:autolaunch_revenue_subjects, [:creator_address])

    create unique_index(
             :autolaunch_revenue_subjects,
             [:chain_id, :created_tx_hash, :created_log_index],
             name: :autolaunch_revenue_subjects_creation_log_unique
           )
  end
end
