defmodule Mix.Tasks.Autolaunch.PublishEpoch do
  @moduledoc false
  use Mix.Task

  @shortdoc "Runs the autolaunch epoch publisher once"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    result = Autolaunch.Publisher.run_once()

    Mix.shell().info(
      "Published epoch #{result.epoch} for #{result.ready_jobs} ready launch job(s)."
    )
  end
end
