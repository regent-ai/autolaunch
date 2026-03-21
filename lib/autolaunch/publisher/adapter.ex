defmodule Autolaunch.Publisher.Adapter do
  @moduledoc false

  @callback build_epoch_root(map(), integer()) ::
              {:ok, %{root: String.t(), total_staked: Decimal.t() | integer(), metadata: map()}}
              | {:error, term()}

  @callback publish_vault_epoch(map(), integer(), map()) :: :ok | {:error, term()}

  @callback build_chain_revenue_snapshots(map(), integer()) ::
              {:ok, [map()]} | {:error, term()}

  @callback build_regent_epoch(integer(), [map()], Decimal.t()) ::
              {:ok,
               %{
                 root: String.t(),
                 total_revenue_usdc: Decimal.t() | integer(),
                 emission_amount: Decimal.t() | integer(),
                 metadata: map()
               }}
              | {:error, term()}

  @callback publish_regent_epoch(integer(), map()) :: :ok | {:error, term()}
end
