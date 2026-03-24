defmodule Autolaunch.Repo.Migrations.AddCurrentLaunchStackFields do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE autolaunch_jobs
    ADD COLUMN IF NOT EXISTS default_ingress_address varchar,
    ADD COLUMN IF NOT EXISTS revenue_ingress_router_address varchar,
    ADD COLUMN IF NOT EXISTS pool_id varchar
    """)
  end

  def down do
    raise "hard cutover only"
  end
end
