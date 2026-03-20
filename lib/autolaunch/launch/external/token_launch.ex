defmodule Autolaunch.Launch.External.TokenLaunch do
  @moduledoc false
  use Autolaunch.Schema

  @primary_key {:launch_id, :string, autogenerate: false}

  schema "agent_token_launches" do
    field :owner_address, :string
    field :agent_id, :string
    field :lifecycle_run_id, :string
    field :chain_id, :integer
    field :token_address, :string
    field :auction_address, :string
    field :total_supply, :string
    field :vesting_beneficiary, :string
    field :beneficiary_confirmed_at, :utc_datetime_usec
    field :vesting_start_at, :utc_datetime_usec
    field :vesting_end_at, :utc_datetime_usec
    field :launch_status, :string
    field :launch_job_id, :string
    field :launch_tx_hash, :string
    field :metadata, :map
    field :completed_at, :utc_datetime_usec
    timestamps()
  end

  def changeset(launch, attrs) do
    launch
    |> cast(attrs, [
      :launch_id,
      :owner_address,
      :agent_id,
      :lifecycle_run_id,
      :chain_id,
      :token_address,
      :auction_address,
      :total_supply,
      :vesting_beneficiary,
      :beneficiary_confirmed_at,
      :vesting_start_at,
      :vesting_end_at,
      :launch_status,
      :launch_job_id,
      :launch_tx_hash,
      :metadata,
      :completed_at
    ])
    |> validate_required([
      :launch_id,
      :owner_address,
      :agent_id,
      :chain_id,
      :total_supply,
      :vesting_beneficiary,
      :launch_status
    ])
  end
end
