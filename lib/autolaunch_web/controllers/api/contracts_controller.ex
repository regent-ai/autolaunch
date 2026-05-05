defmodule AutolaunchWeb.Api.ContractsController do
  use AutolaunchWeb, :controller

  alias Autolaunch.Contracts
  alias AutolaunchWeb.Api.ContractsError

  import AutolaunchWeb.Api.ControllerHelpers

  def admin(conn, _params) do
    render_authed(conn, fn _human -> context_module().admin_overview() end)
  end

  def show_job(conn, %{"id" => job_id}) do
    render_authed(conn, fn human -> context_module().job_state(job_id, human) end)
  end

  def show_subject(conn, %{"id" => subject_id}) do
    render_authed(conn, fn human -> context_module().subject_state(subject_id, human) end)
  end

  def prepare_job(conn, %{"id" => job_id, "resource" => resource, "action" => action} = params) do
    render_authed(conn, fn human ->
      context_module().prepare_job_action(job_id, resource, action, params, human)
    end)
  end

  def prepare_subject(
        conn,
        %{"id" => subject_id, "resource" => resource, "action" => action} = params
      ) do
    render_authed(conn, fn human ->
      context_module().prepare_subject_action(subject_id, resource, action, params, human)
    end)
  end

  def prepare_admin(conn, %{"resource" => resource, "action" => action} = params) do
    render_authed(conn, fn human ->
      context_module().prepare_admin_action(resource, action, params, human)
    end)
  end

  defp render_result(conn, result),
    do: render_api_result(conn, result, &ContractsError.translate/1)

  defp render_authed(conn, fun) do
    case contract_actor(conn) do
      nil -> render_result(conn, {:error, :unauthorized})
      actor -> render_result(conn, fun.(actor))
    end
  end

  defp contract_actor(conn),
    do: conn.assigns[:current_agent_claims] || conn.assigns[:current_human]

  defp context_module do
    configured_module(:contracts_api, :context_module, Contracts)
  end
end
