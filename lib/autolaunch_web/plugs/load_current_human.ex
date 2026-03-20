defmodule AutolaunchWeb.Plugs.LoadCurrentHuman do
  @moduledoc false

  import Plug.Conn

  alias Autolaunch.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    privy_user_id = get_session(conn, :privy_user_id)
    assign(conn, :current_human, Accounts.get_human_by_privy_id(privy_user_id))
  end
end
