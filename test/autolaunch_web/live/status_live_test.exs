defmodule AutolaunchWeb.StatusLiveTest do
  use AutolaunchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defmodule StatusStub do
    def snapshot do
      %{
        ok: false,
        checked_at: ~U[2026-04-23 16:00:00Z],
        checks: [
          %{state: :ready, label: "Database", detail: "Reads and writes are available."},
          %{state: :ready, label: "Local cache", detail: "Cache is ready."},
          %{state: :blocked, label: "Launch stack", detail: "One setting needs a value."}
        ]
      }
    end
  end

  setup do
    original = Application.get_env(:autolaunch, :status_live, [])
    Application.put_env(:autolaunch, :status_live, status_module: StatusStub)
    on_exit(fn -> Application.put_env(:autolaunch, :status_live, original) end)
  end

  test "status page renders readiness checks", %{conn: conn} do
    {:ok, view, html} = live(conn, "/status")

    assert html =~ "Autolaunch needs attention."
    assert html =~ "Database"
    assert html =~ "Local cache"
    assert html =~ "Launch stack"
    assert html =~ "Attention"

    assert view
           |> element("button", "Refresh")
           |> render_click() =~ "One setting needs a value."
  end
end
