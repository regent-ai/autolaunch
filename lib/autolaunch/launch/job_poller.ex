defmodule Autolaunch.Launch.JobPoller do
  @moduledoc false

  use GenServer

  alias Autolaunch.Launch.Jobs

  require Logger

  @default_interval_ms 2_000

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def wake do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, :wake)
    end

    :ok
  end

  @impl true
  def init(opts) do
    state = %{
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      worker_id: worker_id()
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_cast(:wake, state) do
    send(self(), :poll)
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    drain(state)
    Process.send_after(self(), :poll, state.interval_ms)
    {:noreply, state}
  end

  defp drain(state) do
    try do
      case Jobs.lease_next_job(state.worker_id) do
        {:ok, job} ->
          case Jobs.process_leased_job(job) do
            :ok ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "Launch job poller could not finish #{job.job_id}: #{inspect(reason)}"
              )
          end

          drain(state)

        {:error, :empty} ->
          :ok

        {:error, reason} ->
          Logger.warning("Launch job poller could not lease a job: #{inspect(reason)}")
          :ok
      end
    rescue
      exception in [DBConnection.ConnectionError, Postgrex.Error] ->
        Logger.warning("Launch job poller waiting for database: #{Exception.message(exception)}")
        :ok
    end
  end

  defp worker_id do
    "#{node()}:#{System.pid()}:launch-poller"
  end
end
