defmodule Autolaunch.ApplicationTest do
  use ExUnit.Case, async: false

  setup do
    previous_runtime_env = Application.get_env(:autolaunch, :runtime_env)
    previous_siwa = Application.get_env(:autolaunch, :siwa, [])

    on_exit(fn ->
      Application.put_env(:autolaunch, :runtime_env, previous_runtime_env)
      Application.put_env(:autolaunch, :siwa, previous_siwa)
    end)

    :ok
  end

  test "publisher worker is not part of the supervision tree" do
    children = Supervisor.which_children(Autolaunch.Supervisor)

    refute Enum.any?(children, fn {id, _pid, _type, _modules} ->
             id == Autolaunch.Publisher.Worker
           end)
  end

  test "production SIWA guard requires the broker URL, not a receipt secret" do
    Application.put_env(:autolaunch, :runtime_env, :prod)

    Application.put_env(:autolaunch, :siwa,
      internal_url: "http://siwa.test",
      http_connect_timeout_ms: 2_000,
      http_receive_timeout_ms: 5_000
    )

    assert :ok = Autolaunch.Application.enforce_siwa_runtime_guard!()

    Application.put_env(:autolaunch, :siwa,
      internal_url: "",
      http_connect_timeout_ms: 2_000,
      http_receive_timeout_ms: 5_000
    )

    assert_raise RuntimeError, ~r/invalid SIWA configuration/, fn ->
      Autolaunch.Application.enforce_siwa_runtime_guard!()
    end
  end
end
