defmodule Autolaunch.Launch.External.RegentbotAgent do
  @moduledoc false
  use Autolaunch.Schema

  schema "regentbot_agents" do
    field :owner_address, :string
    field :agent_id, :string
    field :agent_uri, :string
    field :chain_id, :integer
  end
end
