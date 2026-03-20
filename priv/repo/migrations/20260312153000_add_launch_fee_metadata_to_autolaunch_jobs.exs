defmodule Autolaunch.Repo.Migrations.AddLaunchFeeMetadataToAutolaunchJobs do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_jobs) do
      add :hook_address, :string
      add :fee_vault_address, :string
      add :official_pool_id, :string
    end
  end
end
