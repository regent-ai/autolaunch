defmodule Mix.Tasks.Autolaunch.BetaCheck do
  @moduledoc false

  use Mix.Task

  @shortdoc "Runs the read-only public beta readiness checks"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    result = Autolaunch.BetaReadiness.run()

    Enum.each(result.checks, fn check ->
      label = if check.ok, do: "OK", else: "FAIL"
      Mix.shell().info("[#{label}] #{check.key}: #{check.detail}")
    end)

    if result.ok do
      Mix.shell().info("Autolaunch beta check passed.")
    else
      Mix.raise("Autolaunch beta check failed.")
    end
  end
end
