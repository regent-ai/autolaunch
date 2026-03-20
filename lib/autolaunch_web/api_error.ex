defmodule AutolaunchWeb.ApiError do
  @moduledoc false

  import Plug.Conn

  def render(conn, status, code, message, meta \\ %{}) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{
      ok: false,
      error: Map.merge(%{code: code, message: message}, meta)
    })
  end
end
