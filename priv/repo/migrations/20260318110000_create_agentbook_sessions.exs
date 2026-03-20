defmodule Autolaunch.Repo.Migrations.CreateAgentbookSessions do
  use Ecto.Migration

  def change do
    create table(:autolaunch_agentbook_sessions, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :agent_address, :string, null: false
      add :network, :string, null: false
      add :chain_id, :integer, null: false
      add :contract_address, :string, null: false
      add :relay_url, :string
      add :nonce, :bigint, null: false
      add :app_id, :string, null: false
      add :action, :string, null: false
      add :rp_id, :string, null: false
      add :signal, :text, null: false
      add :rp_context, :map, null: false
      add :allow_legacy_proofs, :boolean, null: false, default: true
      add :preset, :string, null: false, default: "orb_legacy"
      add :connector_uri, :text
      add :deep_link_uri, :text
      add :proof_payload, :map
      add :tx_request, :map
      add :status, :string, null: false, default: "pending"
      add :tx_hash, :string
      add :error_text, :text
      add :expires_at, :utc_datetime_usec, null: false

      timestamps()
    end

    create index(:autolaunch_agentbook_sessions, [:agent_address])
    create index(:autolaunch_agentbook_sessions, [:network, :status])
  end
end
