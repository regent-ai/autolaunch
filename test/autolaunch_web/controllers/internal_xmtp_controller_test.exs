defmodule AutolaunchWeb.InternalXmtpControllerTest do
  use AutolaunchWeb.ConnCase, async: false

  alias Autolaunch.Accounts
  alias Autolaunch.Repo
  alias Autolaunch.XMTPMirror
  alias Autolaunch.XMTPMirror.XmtpMembershipCommand
  alias Autolaunch.XMTPMirror.XmtpMessage

  import Autolaunch.TestSupport.XmtpSupport, only: [deterministic_inbox_id: 1, unique_suffix: 0]

  setup %{conn: conn} do
    previous_secret = Application.get_env(:autolaunch, :internal_shared_secret, "")
    Application.put_env(:autolaunch, :internal_shared_secret, "test-internal-secret")

    on_exit(fn ->
      Application.put_env(:autolaunch, :internal_shared_secret, previous_secret)
    end)

    {:ok, conn: put_req_header(conn, "x-autolaunch-secret", "test-internal-secret")}
  end

  test "requires the internal shared secret" do
    conn =
      post(Phoenix.ConnTest.build_conn(), "/api/internal/xmtp/rooms/ensure", %{
        "room_key" => "auction:#{unique_suffix()}",
        "xmtp_group_id" => "xmtp-auction-#{unique_suffix()}",
        "name" => "Auction room"
      })

    assert %{"error" => %{"code" => "internal_auth_required"}} = json_response(conn, 401)
  end

  test "ensures a room and ingests a mirrored message", %{conn: conn} do
    room_key = "auction:#{unique_suffix()}"

    conn =
      post(conn, "/api/internal/xmtp/rooms/ensure", %{
        "room_key" => room_key,
        "xmtp_group_id" => "xmtp-#{room_key}",
        "name" => "Auction room"
      })

    assert %{
             "data" => %{
               "room_key" => ^room_key,
               "xmtp_group_id" => "xmtp-" <> _group_id
             }
           } = json_response(conn, 200)

    message_id = "xmtp-message-#{unique_suffix()}"

    conn =
      conn
      |> recycle()
      |> put_req_header("x-autolaunch-secret", "test-internal-secret")
      |> post("/api/internal/xmtp/messages/ingest", %{
        "room_key" => room_key,
        "xmtp_message_id" => message_id,
        "sender_inbox_id" => "agent-inbox",
        "sender_label" => "Autolaunch agent",
        "sender_type" => "agent",
        "body" => "Auction room update",
        "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert %{"data" => %{"id" => id}} = json_response(conn, 200)

    assert %XmtpMessage{id: ^id, body: "Auction room update", sender_type: :agent} =
             Repo.get_by!(XmtpMessage, xmtp_message_id: message_id)
  end

  test "leases and resolves membership commands", %{conn: conn} do
    room_key = "public-chatbox"
    {:ok, _room} = ensure_room!(room_key)
    human = create_human!("Lease")
    assert {:ok, _result} = XMTPMirror.request_join(human, %{"room_key" => room_key})

    conn =
      post(conn, "/api/internal/xmtp/commands/lease", %{
        "room_key" => room_key
      })

    assert %{"data" => %{"id" => command_id, "op" => "add_member"}} = json_response(conn, 200)

    command = Repo.get!(XmtpMembershipCommand, command_id)
    assert command.status == "processing"
    assert command.attempt_count == 1

    conn =
      conn
      |> recycle()
      |> put_req_header("x-autolaunch-secret", "test-internal-secret")
      |> post("/api/internal/xmtp/commands/#{command_id}/resolve", %{
        "status" => "done"
      })

    assert %{"ok" => true} = json_response(conn, 200)
    assert Repo.get!(XmtpMembershipCommand, command_id).status == "done"
  end

  defp ensure_room!(room_key) do
    XMTPMirror.ensure_room(%{
      "room_key" => room_key,
      "xmtp_group_id" => "xmtp-#{room_key}-#{unique_suffix()}",
      "name" => "Autolaunch Room",
      "status" => "active",
      "presence_ttl_seconds" => 120
    })
  end

  defp create_human!(label) do
    wallet = "0x#{String.pad_leading(Integer.to_string(unique_suffix(), 16), 40, "0")}"

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-internal-xmtp-#{label}-#{unique_suffix()}", %{
        "wallet_address" => wallet,
        "wallet_addresses" => [wallet],
        "xmtp_inbox_id" => deterministic_inbox_id(wallet),
        "display_name" => label
      })

    human
  end
end
