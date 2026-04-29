defmodule Autolaunch.Repo.Migrations.AddLaunchJobLeases do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_jobs) do
      add :locked_at, :utc_datetime_usec
      add :locked_by, :string
      add :last_heartbeat_at, :utc_datetime_usec
      add :attempt_count, :integer, null: false, default: 0
    end

    create index(:autolaunch_jobs, [:status, :locked_at],
             name: :autolaunch_jobs_lease_scan_idx
           )
  end
end
