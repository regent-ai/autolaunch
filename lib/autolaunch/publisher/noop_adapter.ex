defmodule Autolaunch.Publisher.NoopAdapter do
  @moduledoc false
  @behaviour Autolaunch.Publisher.Adapter

  @impl true
  def build_epoch_root(_job, _epoch), do: {:error, :publisher_adapter_not_configured}

  @impl true
  def publish_vault_epoch(_job, _epoch, _payload), do: {:error, :publisher_adapter_not_configured}

  @impl true
  def build_chain_revenue_snapshots(_job, _epoch),
    do: {:error, :publisher_adapter_not_configured}

  @impl true
  def build_regent_epoch(_epoch, _jobs, _total_revenue_usdc),
    do: {:error, :publisher_adapter_not_configured}

  @impl true
  def publish_regent_epoch(_epoch, _payload), do: {:error, :publisher_adapter_not_configured}
end
