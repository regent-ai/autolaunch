defmodule Autolaunch.Launch.External.SocialAccount do
  @moduledoc false
  use Autolaunch.Schema

  schema "agent_social_accounts" do
    field :owner_address, :string
    field :agent_id, :string
    field :provider, :string
    field :status, :string
    field :verified_at, :utc_datetime_usec
  end
end
