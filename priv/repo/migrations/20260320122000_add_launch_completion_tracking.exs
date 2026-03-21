defmodule Autolaunch.Repo.Migrations.AddLaunchCompletionTracking do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_jobs) do
      add :ens_name, :string
      add :world_network, :string, null: false, default: "world"
      add :world_registered, :boolean, null: false, default: false
      add :world_human_id, :string
    end

    alter table(:autolaunch_auctions) do
      add :ens_name, :string
      add :world_network, :string, null: false, default: "world"
      add :world_registered, :boolean, null: false, default: false
      add :world_human_id, :string
    end

    alter table(:autolaunch_agentbook_sessions) do
      add :launch_job_id, :string
      add :human_id, :string
    end

    create index(:autolaunch_jobs, [:world_human_id])
    create index(:autolaunch_auctions, [:world_human_id])
    create index(:autolaunch_agentbook_sessions, [:launch_job_id])
    create index(:autolaunch_agentbook_sessions, [:human_id])
  end
end
