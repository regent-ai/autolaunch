defmodule Mix.Tasks.Autolaunch.VerifyDeploy do
  @moduledoc false

  use Mix.Task

  @shortdoc "Checks live launch-contract invariants for a ready Autolaunch job"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [job: :string, controller_address: :string]
      )

    job_id = Keyword.get(opts, :job)

    if is_nil(job_id) or String.trim(job_id) == "" do
      Mix.raise("mix autolaunch.verify_deploy requires --job <job-id>.")
    end

    result =
      Autolaunch.ReleaseDeployVerifier.run(job_id,
        controller_address: Keyword.get(opts, :controller_address)
      )

    Enum.each(result.checks, fn check ->
      label =
        case {check.ok, check.severity} do
          {true, :warning} -> "WARN-OK"
          {true, _} -> "OK"
          {false, :warning} -> "WARN"
          {false, _} -> "FAIL"
        end

      Mix.shell().info("[#{label}] #{check.key}: #{check.detail}")
    end)

    if is_binary(result.controller_address) do
      Mix.shell().info("Controller: #{result.controller_address}")
    end

    if result.ok do
      Mix.shell().info("Autolaunch deploy verification passed.")
    else
      Mix.raise("Autolaunch deploy verification failed.")
    end
  end
end
