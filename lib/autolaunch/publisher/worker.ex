defmodule Autolaunch.Publisher.Worker do
  @moduledoc false
  use GenServer

  require Logger

  alias Autolaunch.Publisher

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if Publisher.enabled?(), do: schedule_run(1_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:run, state) do
    result = Publisher.run_once()
    Logger.info("autolaunch publisher ran epoch=#{result.epoch} ready_jobs=#{result.ready_jobs}")
    schedule_run(interval_ms())
    {:noreply, state}
  rescue
    error ->
      Logger.error("autolaunch publisher failed: #{Exception.message(error)}")
      schedule_run(interval_ms())
      {:noreply, state}
  end

  defp schedule_run(delay_ms), do: Process.send_after(self(), :run, delay_ms)

  defp interval_ms do
    :autolaunch
    |> Application.get_env(:publisher, [])
    |> Keyword.get(:interval_ms, 300_000)
  end
end
