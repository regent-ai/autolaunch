defmodule AutolaunchWeb.Plugs.RateLimitTest do
  use AutolaunchWeb.ConnCase, async: false

  alias AutolaunchWeb.RateLimiter

  setup do
    original = Application.get_env(:autolaunch, :rate_limits, [])
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:autolaunch, :rate_limits, original)
      RateLimiter.reset()
    end)

    :ok
  end

  test "public write routes are rate limited", %{conn: conn} do
    Application.put_env(:autolaunch, :rate_limits,
      public_write: [limit: 1, window_ms: 60_000],
      expensive_read: [limit: 50, window_ms: 60_000]
    )

    post(conn, "/v1/app/agentbook/sessions", %{"network" => "world"})
    conn = post(conn, "/v1/app/agentbook/sessions", %{"network" => "world"})

    assert %{"ok" => false, "error" => %{"code" => "rate_limited"}} =
             json_response(conn, 429)
  end

  test "expensive read routes are rate limited", %{conn: conn} do
    Application.put_env(:autolaunch, :rate_limits,
      public_write: [limit: 50, window_ms: 60_000],
      expensive_read: [limit: 1, window_ms: 60_000]
    )

    get(conn, "/v1/app/me/profile")
    conn = get(conn, "/v1/app/me/profile")

    assert %{"ok" => false, "error" => %{"code" => "rate_limited"}} =
             json_response(conn, 429)
  end

  test "health checks are not rate limited", %{conn: conn} do
    Application.put_env(:autolaunch, :rate_limits,
      public_write: [limit: 1, window_ms: 60_000],
      expensive_read: [limit: 1, window_ms: 60_000]
    )

    get(conn, "/health")
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"ok" => true, "service" => "autolaunch"}
  end
end
