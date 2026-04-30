defmodule Autolaunch.PublicEvents do
  @moduledoc false

  alias Autolaunch.XMTPMirror.XmtpMessage
  alias Phoenix.PubSub

  @pubsub Autolaunch.PubSub
  @topic "autolaunch:public_site:events"

  @type event ::
          {:public_site_event,
           %{
             event: :xmtp_room_message | :xmtp_room_membership,
             room_key: String.t(),
             message: XmtpMessage.t() | nil
           }}

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  @spec broadcast_xmtp_room_message(XmtpMessage.t(), String.t()) :: :ok | {:error, term()}
  def broadcast_xmtp_room_message(%XmtpMessage{} = message, room_key) when is_binary(room_key) do
    broadcast(%{event: :xmtp_room_message, room_key: room_key, message: message})
  end

  @spec broadcast_xmtp_room_membership(String.t()) :: :ok | {:error, term()}
  def broadcast_xmtp_room_membership(room_key) when is_binary(room_key) do
    broadcast(%{event: :xmtp_room_membership, room_key: room_key, message: nil})
  end

  defp broadcast(payload) when is_map(payload) do
    PubSub.broadcast(@pubsub, @topic, {:public_site_event, payload})
  end
end
