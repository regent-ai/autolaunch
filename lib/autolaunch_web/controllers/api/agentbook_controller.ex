defmodule AutolaunchWeb.Api.AgentbookController do
  use AutolaunchWeb, :controller

  alias AgentWorld.Error
  alias Autolaunch.Agentbook
  alias AutolaunchWeb.ApiError

  def create(conn, params) do
    case Agentbook.create_session(params) do
      {:ok, session} -> json(conn, %{ok: true, session: session})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def show(conn, %{"id" => session_id}) do
    case Agentbook.get_session(session_id) do
      nil -> render_error(conn, :session_not_found)
      session -> json(conn, %{ok: true, session: session})
    end
  end

  def submit(conn, %{"id" => session_id} = params) do
    case Agentbook.submit_session(session_id, Map.delete(params, "id")) do
      {:ok, session} -> json(conn, %{ok: true, session: session})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def lookup(conn, params) do
    case Agentbook.lookup_human(params) do
      {:ok, result} -> json(conn, %{ok: true, result: result})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def verify(conn, params) do
    case Agentbook.verify_header(params) do
      {:ok, result} -> json(conn, %{ok: true, result: result})
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp render_error(conn, :session_not_found) do
    ApiError.render(conn, :not_found, "session_not_found", "AgentBook session was not found")
  end

  defp render_error(conn, :invalid_agent_address) do
    ApiError.render(
      conn,
      :unprocessable_entity,
      "invalid_agent_address",
      "Agent wallet address is invalid"
    )
  end

  defp render_error(conn, :invalid_network) do
    ApiError.render(
      conn,
      :unprocessable_entity,
      "invalid_network",
      "Network must be world, base, or base-sepolia"
    )
  end

  defp render_error(conn, :invalid_request) do
    ApiError.render(
      conn,
      :unprocessable_entity,
      "invalid_request",
      "Required request data is missing"
    )
  end

  defp render_error(conn, %Error{} = error) do
    ApiError.render(conn, :unprocessable_entity, "agentbook_invalid", error.message)
  end

  defp render_error(conn, {:transaction_pending, tx_hash}) do
    conn
    |> put_status(:accepted)
    |> json(%{
      ok: false,
      error: %{
        code: "transaction_pending",
        message: "Transaction is still pending",
        tx_hash: tx_hash
      }
    })
  end

  defp render_error(conn, reason) do
    ApiError.render(conn, :unprocessable_entity, "agentbook_invalid", inspect(reason))
  end
end
