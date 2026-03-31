defmodule Autolaunch.Repo.Migrations.CreateOrExpandAgentSocialAccounts do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:agent_social_accounts) do
      add :owner_address, :string, null: false
      add :agent_id, :string, null: false
      add :provider, :string, null: false
      add :handle, :string
      add :profile_url, :string
      add :provider_subject, :string
      add :status, :string, null: false, default: "verified"
      add :verified_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:agent_social_accounts) do
      add_if_not_exists :owner_address, :string
      add_if_not_exists :agent_id, :string
      add_if_not_exists :provider, :string
      add_if_not_exists :handle, :string
      add_if_not_exists :profile_url, :string
      add_if_not_exists :provider_subject, :string
      add_if_not_exists :status, :string, default: "verified"
      add_if_not_exists :verified_at, :utc_datetime_usec
      add_if_not_exists :inserted_at, :utc_datetime_usec
      add_if_not_exists :updated_at, :utc_datetime_usec
    end

    create_if_not_exists index(:agent_social_accounts, [:agent_id])
    create_if_not_exists index(:agent_social_accounts, [:provider])

    create_if_not_exists unique_index(
                           :agent_social_accounts,
                           [:agent_id, :provider],
                           name: :agent_social_accounts_agent_provider_unique
                         )

    create_if_not_exists unique_index(
                           :agent_social_accounts,
                           [:provider, :provider_subject],
                           name: :agent_social_accounts_provider_subject_unique
                         )
  end
end
