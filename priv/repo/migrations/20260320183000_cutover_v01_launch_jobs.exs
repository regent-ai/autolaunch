defmodule Autolaunch.Repo.Migrations.CutoverV01LaunchJobs do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_jobs) do
      remove :treasury_address
      remove :fee_vault_address
      remove :official_pool_id
      remove :vesting_beneficiary

      add :recovery_safe_address, :string
      add :auction_proceeds_recipient, :string
      add :ethereum_revenue_treasury, :string
      add :base_revenue_treasury, :string
      add :tempo_revenue_treasury, :string
      add :base_emission_recipient, :string
      add :registry_address, :string
      add :rights_hub_address, :string
      add :ethereum_vault_address, :string
      add :base_vault_address, :string
      add :tempo_vault_address, :string
      add :regent_emissions_distributor_address, :string
      add :epoch_seconds, :integer, null: false, default: 259_200
    end

    create table(:autolaunch_epoch_roots) do
      add :agent_id, :string, null: false
      add :epoch, :integer, null: false
      add :chain_id, :integer, null: false
      add :rights_hub_address, :string, null: false
      add :revenue_vault_address, :string, null: false
      add :root, :string, null: false
      add :total_staked, :decimal, precision: 40, scale: 0, null: false
      add :published_at, :utc_datetime_usec
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:autolaunch_epoch_roots, [:agent_id, :epoch, :chain_id])

    create table(:autolaunch_chain_revenue_snapshots) do
      add :agent_id, :string, null: false
      add :epoch, :integer, null: false
      add :chain_id, :integer, null: false
      add :gross_revenue_usdc, :decimal, precision: 24, scale: 6, null: false
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:autolaunch_chain_revenue_snapshots, [:agent_id, :epoch, :chain_id])

    create table(:autolaunch_regent_epochs) do
      add :epoch, :integer, null: false
      add :total_revenue_usdc, :decimal, precision: 24, scale: 6, null: false
      add :emission_amount, :decimal, precision: 24, scale: 6, null: false
      add :root, :string, null: false
      add :published_at, :utc_datetime_usec
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:autolaunch_regent_epochs, [:epoch])
  end
end
