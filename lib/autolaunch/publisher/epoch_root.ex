defmodule Autolaunch.Publisher.EpochRoot do
  @moduledoc false
  use Autolaunch.Schema

  schema "autolaunch_epoch_roots" do
    field :agent_id, :string
    field :epoch, :integer
    field :chain_id, :integer
    field :rights_hub_address, :string
    field :revenue_vault_address, :string
    field :root, :string
    field :total_staked, :decimal
    field :published_at, :utc_datetime_usec
    field :metadata, :map

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :agent_id,
      :epoch,
      :chain_id,
      :rights_hub_address,
      :revenue_vault_address,
      :root,
      :total_staked,
      :published_at,
      :metadata
    ])
    |> validate_required([
      :agent_id,
      :epoch,
      :chain_id,
      :rights_hub_address,
      :revenue_vault_address,
      :root,
      :total_staked
    ])
  end
end
