defmodule AutolaunchWeb.Api.EnsLinkController do
  use AutolaunchWeb, :controller

  alias Autolaunch.EnsLink
  alias AutolaunchWeb.ApiError

  def plan(conn, params) do
    case EnsLink.plan_link(conn.assigns[:current_human], params) do
      {:ok, plan} -> json(conn, %{ok: true, plan: plan})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def prepare_ensip25(conn, params) do
    case EnsLink.prepare_ensip25_update(conn.assigns[:current_human], params) do
      {:ok, prepared} -> json(conn, %{ok: true, prepared: prepared})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def prepare_erc8004(conn, params) do
    case EnsLink.prepare_erc8004_update(conn.assigns[:current_human], params) do
      {:ok, prepared} -> json(conn, %{ok: true, prepared: prepared})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def prepare_bidirectional(conn, params) do
    case EnsLink.prepare_bidirectional_link(conn.assigns[:current_human], params) do
      {:ok, prepared} -> json(conn, %{ok: true, prepared: prepared})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :unauthorized),
    do: ApiError.render(conn, :unauthorized, "auth_required", "Privy session required")

  defp render_error(conn, :agent_not_found),
    do: ApiError.render(conn, :not_found, "agent_not_found", "ERC-8004 identity not found")

  defp render_error(conn, :identity_registry_not_configured),
    do:
      ApiError.render(
        conn,
        :unprocessable_entity,
        "identity_registry_not_configured",
        "ERC-8004 registry is not configured for this chain"
      )

  defp render_error(conn, :rpc_not_configured),
    do:
      ApiError.render(
        conn,
        :unprocessable_entity,
        "rpc_not_configured",
        "RPC URL is not configured for this chain"
      )

  defp render_error(conn, :signer_not_linked),
    do:
      ApiError.render(
        conn,
        :unprocessable_entity,
        "signer_not_linked",
        "Signer must be one of the wallets linked to the current session"
      )

  defp render_error(conn, :invalid_chain_id),
    do: ApiError.render(conn, :unprocessable_entity, "invalid_chain_id", "Invalid chain id")

  defp render_error(conn, :invalid_agent_id),
    do: ApiError.render(conn, :unprocessable_entity, "invalid_agent_id", "Invalid agent id")

  defp render_error(conn, :ens_name_required),
    do: ApiError.render(conn, :unprocessable_entity, "ens_name_required", "ENS name is required")

  defp render_error(conn, %AgentEns.Error{} = error) do
    ApiError.render(conn, :unprocessable_entity, "ens_link_invalid", error.message)
  end

  defp render_error(conn, reason) do
    ApiError.render(conn, :unprocessable_entity, "ens_link_invalid", inspect(reason))
  end
end
