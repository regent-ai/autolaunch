defmodule Autolaunch.Launch.Jobs do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Autolaunch.Launch.Deployment
  alias Autolaunch.Launch.DeployResult
  alias Autolaunch.Launch.Job
  alias Autolaunch.Repo

  @terminal_statuses ~w(ready failed blocked)
  @lease_timeout_ms :timer.minutes(10)

  def get_job_response(job_id), do: Deployment.get_job_response(job_id)

  def queue_processing(job_id) do
    Autolaunch.Launch.JobPoller.wake()
    heartbeat_queued_job(job_id)
  end

  def terminal_status?(status), do: status in @terminal_statuses

  def lease_next_job(worker_id \\ worker_id(), now \\ DateTime.utc_now()) do
    stale_before = DateTime.add(now, -lease_timeout_ms(), :millisecond)

    Repo.transaction(fn ->
      Job
      |> where([job], job.status in ["queued", "running"])
      |> where(
        [job],
        is_nil(job.locked_at) or job.locked_at < ^stale_before or job.locked_by == ^worker_id
      )
      |> order_by([job], asc: job.inserted_at)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> limit(1)
      |> Repo.one()
      |> case do
        nil -> {:error, :empty}
        %Job{} = job -> lease_job_record(job, worker_id, now)
      end
    end)
    |> flatten_transaction()
  end

  def process_job(job_id) do
    case lease_job(job_id) do
      {:ok, job} ->
        run_and_persist(job)

      {:error, :not_available} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      mark_failed_after_crash(job_id, error)
  end

  def process_leased_job(%Job{} = job), do: run_and_persist(job)

  defp lease_job(job_id) do
    now = DateTime.utc_now()
    worker_id = worker_id()
    stale_before = DateTime.add(now, -lease_timeout_ms(), :millisecond)

    Repo.transaction(fn ->
      Job
      |> where([job], job.job_id == ^job_id)
      |> where([job], job.status in ["queued", "running"])
      |> where(
        [job],
        is_nil(job.locked_at) or job.locked_at < ^stale_before or job.locked_by == ^worker_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil -> {:error, :not_available}
        %Job{} = job -> lease_job_record(job, worker_id, now)
      end
    end)
    |> flatten_transaction()
  end

  defp lease_job_record(%Job{} = job, worker_id, now) do
    attrs = %{
      status: "running",
      step: "deploying",
      locked_at: now,
      locked_by: worker_id,
      last_heartbeat_at: now,
      attempt_count: (job.attempt_count || 0) + 1,
      started_at: job.started_at || now
    }

    job
    |> Job.update_changeset(attrs)
    |> Repo.update()
  end

  defp run_and_persist(%Job{} = job) do
    case Deployment.run_launch(job) do
      {:ok, result} ->
        case DeployResult.persist_success(job, result) do
          {:ok, _persisted} ->
            :ok

          {:error, reason} ->
            with {:ok, _job} <-
                   mark_failed(job, "Failed to save launch result: #{inspect(reason)}", %{}) do
              {:error, {:launch_result_persist_failed, reason}}
            end
        end

      {:error, reason, logs} ->
        case DeployResult.persist_failure(job, reason, logs) do
          {:ok, _job} ->
            :ok

          {:error, persist_reason} ->
            with {:ok, _job} <- mark_failed(job, reason, logs) do
              {:error, {:launch_failure_persist_failed, persist_reason}}
            end
        end
    end
  end

  defp mark_failed(%Job{} = job, reason, logs) do
    job
    |> Job.update_changeset(%{
      status: "failed",
      step: "failed",
      locked_at: nil,
      locked_by: nil,
      last_heartbeat_at: DateTime.utc_now(),
      error_message: reason,
      finished_at: DateTime.utc_now(),
      stdout_tail: Map.get(logs, :stdout_tail, ""),
      stderr_tail: Map.get(logs, :stderr_tail, "")
    })
    |> Repo.update()
  end

  defp mark_failed_after_crash(job_id, error) do
    reason = Exception.message(error)

    case Repo.get(Job, job_id) do
      %Job{} = job ->
        job
        |> Job.update_changeset(%{
          status: "failed",
          step: "failed",
          locked_at: nil,
          locked_by: nil,
          last_heartbeat_at: DateTime.utc_now(),
          error_message: reason,
          finished_at: DateTime.utc_now()
        })
        |> Repo.update()
        |> case do
          {:ok, _job} -> {:error, {:launch_crashed, reason}}
          {:error, persist_reason} -> {:error, {:launch_crash_persist_failed, persist_reason}}
        end

      nil ->
        {:error, {:launch_crashed, reason}}
    end
  end

  defp heartbeat_queued_job(job_id) do
    now = DateTime.utc_now()

    from(job in Job, where: job.job_id == ^job_id and job.status == "queued")
    |> Repo.update_all(set: [last_heartbeat_at: now])

    :ok
  end

  defp worker_id do
    node = node() |> Atom.to_string()
    "#{node}:#{System.pid()}"
  end

  defp lease_timeout_ms do
    :autolaunch
    |> Application.get_env(:launch_job_poller, [])
    |> Keyword.get(:lease_timeout_ms, @lease_timeout_ms)
  end

  defp flatten_transaction({:ok, result}), do: result
  defp flatten_transaction({:error, reason}), do: {:error, reason}
end
