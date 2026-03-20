defmodule Autolaunch.Launch.External.TokenLaunchStake do
  @moduledoc false
  use Autolaunch.Schema

  @primary_key {:lock_id, :string, autogenerate: false}
  schema "agent_token_launch_stakes" do
    field :owner_address, :string
    field :status, :string
    field :unlock_at, :utc_datetime_usec
  end
end
