defmodule Autolaunch.Publisher.RegentEpoch do
  @moduledoc false
  use Autolaunch.Schema

  schema "autolaunch_regent_epochs" do
    field :epoch, :integer
    field :total_revenue_usdc, :decimal
    field :emission_amount, :decimal
    field :root, :string
    field :published_at, :utc_datetime_usec
    field :metadata, :map

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:epoch, :total_revenue_usdc, :emission_amount, :root, :published_at, :metadata])
    |> validate_required([:epoch, :total_revenue_usdc, :emission_amount, :root])
  end
end
