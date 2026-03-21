defmodule Autolaunch.Launch.Job do
  @moduledoc false
  use Autolaunch.Schema

  @primary_key {:job_id, :string, autogenerate: false}

  schema "autolaunch_jobs" do
    field :privy_user_id, :string
    field :owner_address, :string
    field :agent_id, :string
    field :agent_name, :string
    field :ens_name, :string
    field :token_name, :string
    field :token_symbol, :string
    field :recovery_safe_address, :string
    field :auction_proceeds_recipient, :string
    field :ethereum_revenue_treasury, :string
    field :base_revenue_treasury, :string
    field :tempo_revenue_treasury, :string
    field :base_emission_recipient, :string
    field :network, :string, default: "ethereum-mainnet"
    field :chain_id, :integer, default: 1
    field :broadcast, :boolean, default: true
    field :status, :string, default: "queued"
    field :step, :string, default: "queued"
    field :error_message, :string
    field :launch_notes, :string
    field :total_supply, :string
    field :lifecycle_run_id, :string
    field :message, :string
    field :siwa_nonce, :string
    field :siwa_signature, :string
    field :issued_at, :utc_datetime_usec
    field :request_ip, :string
    field :script_target, :string
    field :deploy_workdir, :string
    field :deploy_binary, :string
    field :rpc_host, :string
    field :auction_address, :string
    field :token_address, :string
    field :hook_address, :string
    field :registry_address, :string
    field :rights_hub_address, :string
    field :ethereum_vault_address, :string
    field :base_vault_address, :string
    field :tempo_vault_address, :string
    field :regent_emissions_distributor_address, :string
    field :tx_hash, :string
    field :uniswap_url, :string
    field :stdout_tail, :string
    field :stderr_tail, :string
    field :epoch_seconds, :integer, default: 259_200
    field :world_network, :string, default: "world"
    field :world_registered, :boolean, default: false
    field :world_human_id, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps()
  end

  def create_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :job_id,
      :privy_user_id,
      :owner_address,
      :agent_id,
      :agent_name,
      :ens_name,
      :token_name,
      :token_symbol,
      :recovery_safe_address,
      :auction_proceeds_recipient,
      :ethereum_revenue_treasury,
      :base_revenue_treasury,
      :tempo_revenue_treasury,
      :base_emission_recipient,
      :network,
      :chain_id,
      :broadcast,
      :status,
      :step,
      :launch_notes,
      :total_supply,
      :lifecycle_run_id,
      :message,
      :siwa_nonce,
      :siwa_signature,
      :issued_at,
      :request_ip,
      :script_target,
      :deploy_workdir,
      :deploy_binary,
      :rpc_host
    ])
    |> validate_required([
      :job_id,
      :owner_address,
      :agent_id,
      :token_name,
      :token_symbol,
      :recovery_safe_address,
      :auction_proceeds_recipient,
      :ethereum_revenue_treasury,
      :base_revenue_treasury,
      :tempo_revenue_treasury,
      :base_emission_recipient,
      :network,
      :chain_id,
      :status,
      :step,
      :total_supply,
      :message,
      :siwa_nonce,
      :siwa_signature,
      :issued_at
    ])
  end

  def update_changeset(job, attrs) do
    cast(job, attrs, [
      :status,
      :step,
      :error_message,
      :auction_address,
      :token_address,
      :hook_address,
      :registry_address,
      :rights_hub_address,
      :ethereum_vault_address,
      :base_vault_address,
      :tempo_vault_address,
      :regent_emissions_distributor_address,
      :tx_hash,
      :uniswap_url,
      :stdout_tail,
      :stderr_tail,
      :world_network,
      :world_registered,
      :world_human_id,
      :started_at,
      :finished_at
    ])
  end
end
