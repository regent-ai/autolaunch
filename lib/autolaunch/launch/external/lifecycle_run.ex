defmodule Autolaunch.Launch.External.LifecycleRun do
  @moduledoc false
  use Autolaunch.Schema

  @primary_key {:run_id, :string, autogenerate: false}
  schema "agent_lifecycle_runs" do
    field :owner_address, :string
    field :agent_id, :string
    field :state, :string
    field :updated_at, :utc_datetime_usec
  end
end
