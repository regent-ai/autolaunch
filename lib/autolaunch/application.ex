defmodule Autolaunch.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = enforce_siwa_runtime_guard!()

    children =
      [
        Autolaunch.Repo,
        Autolaunch.LocalCache.child_spec(),
        {DNSCluster, query: Application.get_env(:autolaunch, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Autolaunch.PubSub},
        {Task.Supervisor, name: Autolaunch.TaskSupervisor},
        launch_job_poller_child(),
        AutolaunchWeb.RateLimiter,
        Autolaunch.XmtpIdentity,
        AutolaunchWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Autolaunch.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AutolaunchWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp enforce_siwa_runtime_guard! do
    runtime_env = Application.get_env(:autolaunch, :runtime_env, :dev)
    siwa_cfg = Application.get_env(:autolaunch, :siwa, [])
    shared_secret = Keyword.get(siwa_cfg, :shared_secret)

    if runtime_env == :prod and (not is_binary(shared_secret) or String.trim(shared_secret) == "") do
      raise """
      invalid SIWA configuration: :siwa, shared_secret must be configured in :prod.
      """
    end

    :ok
  end

  defp launch_job_poller_child do
    opts = Application.get_env(:autolaunch, :launch_job_poller, [])

    if Keyword.get(opts, :enabled, false) do
      {Autolaunch.Launch.JobPoller, opts}
    end
  end
end
