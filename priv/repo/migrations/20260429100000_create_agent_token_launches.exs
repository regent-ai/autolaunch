defmodule Autolaunch.Repo.Migrations.CreateAgentTokenLaunches do
  use Ecto.Migration

  def change do
    create table(:agent_token_launches, primary_key: false) do
      add :launch_id, :string, primary_key: true
      add :owner_address, :string, null: false
      add :agent_id, :string, null: false
      add :lifecycle_run_id, :string
      add :chain_id, :integer, null: false
      add :token_address, :string
      add :auction_address, :string
      add :total_supply, :string, null: false
      add :vesting_beneficiary, :string, null: false
      add :beneficiary_confirmed_at, :utc_datetime_usec
      add :vesting_start_at, :utc_datetime_usec
      add :vesting_end_at, :utc_datetime_usec
      add :launch_status, :string, null: false
      add :launch_job_id, :string, null: false
      add :launch_tx_hash, :string
      add :metadata, :map, null: false, default: %{}
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_token_launches, [:launch_job_id])
    create index(:agent_token_launches, [:owner_address])
    create index(:agent_token_launches, [:agent_id])
    create index(:agent_token_launches, [:chain_id])
  end
end
