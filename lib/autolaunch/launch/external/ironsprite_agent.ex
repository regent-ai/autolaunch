defmodule Autolaunch.Launch.External.IronspriteAgent do
  @moduledoc false
  use Autolaunch.Schema

  schema "ironsprite_agents" do
    field :owner_address, :string
    field :agent_id, :string
    field :sprite_name, :string
    field :basename_fqdn, :string
    field :chain_id, :integer
    field :status, :string
    field :last_health_check_at, :utc_datetime_usec
  end
end
