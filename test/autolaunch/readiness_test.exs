defmodule Autolaunch.Launch.ReadinessTest do
  use ExUnit.Case, async: true

  alias Autolaunch.Launch.Readiness

  test "passed_count counts true checks only" do
    readiness = %{checks: [%{passed: true}, %{passed: false}, %{passed: true}]}

    assert Readiness.passed_count(readiness) == 2
  end
end
