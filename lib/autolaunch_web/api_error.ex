defmodule AutolaunchWeb.ApiError do
  @moduledoc false

  import Plug.Conn

  def render(conn, status, code, message, meta \\ %{}) do
    status_code = Plug.Conn.Status.code(status)
    next_steps = Map.get(meta, :next_steps) || Map.get(meta, "next_steps")
    meta = Map.drop(meta, [:next_steps, "next_steps"])

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{
      ok: false,
      error:
        Map.merge(
          %{
            code: code,
            product: "autolaunch",
            status: status_code,
            path: conn.request_path,
            request_id: request_id(conn),
            message: message,
            next_steps: next_steps
          },
          meta
        )
    })
  end

  defp request_id(conn) do
    conn
    |> Plug.Conn.get_resp_header("x-request-id")
    |> List.first()
  end
end
