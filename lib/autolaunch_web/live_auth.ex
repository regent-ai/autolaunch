defmodule AutolaunchWeb.LiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias Autolaunch.Accounts

  def on_mount(:current_human, _params, session, socket) do
    current_human =
      session
      |> Map.get("privy_user_id")
      |> Accounts.get_human_by_privy_id()

    {:cont, assign(socket, :current_human, current_human)}
  end
end
