defmodule AutolaunchWeb.HealthController do
  use AutolaunchWeb, :controller

  def show(conn, _params) do
    json(conn, %{ok: true, service: "autolaunch", now: DateTime.utc_now()})
  end
end
