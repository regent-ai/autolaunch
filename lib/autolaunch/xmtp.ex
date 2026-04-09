defmodule Autolaunch.Xmtp do
  @moduledoc false

  alias Autolaunch.Xmtp.Agent

  @pubsub_topic "autolaunch:xmtp:public_room"

  @type membership_state :: :view_only | :join_pending_signature | :joined | :full | :kicked

  @type panel_message :: %{
          key: String.t(),
          author: String.t(),
          body: String.t(),
          stamp: String.t(),
          side: :self | :other,
          sender_inbox_id: String.t(),
          sender_wallet: String.t() | nil,
          website_state: :visible | :moderator_deleted,
          can_delete?: boolean(),
          can_kick?: boolean()
        }

  @type panel :: %{
          room_name: String.t(),
          room_id: String.t() | nil,
          connected_wallet: String.t() | nil,
          ready?: boolean(),
          joined?: boolean(),
          can_join?: boolean(),
          can_send?: boolean(),
          moderator?: boolean(),
          membership_state: membership_state(),
          status: String.t(),
          pending_signature_request_id: String.t() | nil,
          member_count: non_neg_integer(),
          seat_count: pos_integer(),
          seats_remaining: non_neg_integer(),
          messages: [panel_message()]
        }

  def child_spec(opts \\ []) do
    Agent.child_spec(opts)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Autolaunch.PubSub, @pubsub_topic)
  end

  def topic, do: @pubsub_topic

  def public_room_panel(current_human \\ nil) do
    GenServer.call(Agent, {:public_room_panel, current_human})
  end

  def request_join(current_human) do
    GenServer.call(Agent, {:request_join, current_human})
  end

  def complete_join_signature(current_human, request_id, signature) do
    GenServer.call(Agent, {:complete_join_signature, current_human, request_id, signature})
  end

  def send_public_message(current_human, body) do
    GenServer.call(Agent, {:send_public_message, current_human, body})
  end

  def invite_user(current_human_or_system, target_wallet_or_inbox) do
    GenServer.call(Agent, {:invite_user, current_human_or_system, target_wallet_or_inbox})
  end

  def kick_user(current_human_or_system, target_wallet_or_inbox) do
    GenServer.call(Agent, {:kick_user, current_human_or_system, target_wallet_or_inbox})
  end

  def moderator_delete_message(current_human, message_id) do
    GenServer.call(Agent, {:moderator_delete_message, current_human, message_id})
  end

  def moderator_kick_user(current_human, target_wallet_or_inbox) do
    kick_user(current_human, target_wallet_or_inbox)
  end

  def heartbeat(current_human) do
    GenServer.cast(Agent, {:heartbeat, current_human})
  end

  def bootstrap_room!(opts \\ []) do
    GenServer.call(Agent, {:bootstrap_room, opts}, :timer.seconds(30))
  end

  def reset_for_test! do
    GenServer.call(Agent, :reset_for_test, :timer.seconds(30))
  end

  def room_key do
    :autolaunch
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:room_key, "autolaunch_wire")
  end

  def pubsub_topic, do: @pubsub_topic
end
