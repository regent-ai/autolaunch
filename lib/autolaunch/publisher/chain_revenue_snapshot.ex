defmodule Autolaunch.Publisher.ChainRevenueSnapshot do
  @moduledoc false
  use Autolaunch.Schema

  schema "autolaunch_chain_revenue_snapshots" do
    field :agent_id, :string
    field :epoch, :integer
    field :chain_id, :integer
    field :gross_revenue_usdc, :decimal
    field :metadata, :map

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:agent_id, :epoch, :chain_id, :gross_revenue_usdc, :metadata])
    |> validate_required([:agent_id, :epoch, :chain_id, :gross_revenue_usdc])
  end
end
