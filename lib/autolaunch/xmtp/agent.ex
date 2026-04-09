defmodule Autolaunch.Xmtp.Agent do
  @moduledoc false

  use GenServer

  import Ecto.Query, warn: false

  alias Autolaunch.Accounts.HumanUser
  alias Autolaunch.Repo
  alias Autolaunch.Xmtp
  alias Autolaunch.Xmtp.Log
  alias Autolaunch.Xmtp.MessageLog
  alias Autolaunch.Xmtp.Room
  alias Autolaunch.Xmtp.RoomMembership
  alias Autolaunch.Xmtp.Wallet
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Groups
  alias XmtpElixirSdk.Internal.ConversationServer
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Preferences
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types

  @name __MODULE__
  @runtime_name Autolaunch.Xmtp.Runtime
  @message_limit 24
  @default_presence_timeout_ms :timer.minutes(2)
  @default_presence_check_ms :timer.seconds(30)
  @default_room_capacity 200
  @public_room_options %Types.CreateGroupOptions{
    name: "Autolaunch Wire",
    description: "The shared private XMTP room mirrored into the public Autolaunch site.",
    app_data: "autolaunch-private-wire"
  }

  @type state :: %{
          mode: :ready | :unavailable,
          unavailable_reason: atom() | nil,
          relay_client: Client.t() | nil,
          public_room: Conversation.t() | nil,
          room: Room.t() | nil,
          clients_by_wallet: %{optional(String.t()) => Client.t()},
          pending_signatures: %{optional(String.t()) => map()}
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def child_spec(opts \\ []) do
    %{
      id: @name,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @impl true
  def init(_opts) do
    schedule_presence_tick()
    state = restore_state!()
    remember_relay_client(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:public_room_panel, current_human}, _from, state) do
    {:reply, {:ok, build_panel(state, current_human)}, state}
  end

  def handle_call({:request_join, current_human}, _from, state) do
    with {:ok, ready_state} <- require_ready(state),
         {:ok, wallet_address} <- fetch_wallet_address(current_human),
         false <- room_full?(ready_state),
         {:ok, client, next_state} <- ensure_join_candidate(ready_state, wallet_address) do
      cond do
        joined?(next_state, wallet_address) ->
          touched_state = touch_membership_presence(next_state, wallet_address, client.inbox_id)
          {:reply, {:ok, build_panel(touched_state, current_human)}, touched_state}

        client.ready? ->
          {:ok, panel, updated_state} = invite_joined_member(next_state, client, current_human)
          {:reply, {:ok, panel}, updated_state}

        true ->
          {:ok, %{signature_request_id: request_id, signature_text: signature_text}} =
            Clients.unsafe_create_inbox_signature_text(client)

          updated_state =
            put_in(
              next_state.pending_signatures[request_id],
              %{wallet_address: wallet_address, action: :join}
            )

          panel =
            build_panel(
              updated_state,
              current_human,
              "Sign the XMTP identity message to join the private room.",
              request_id
            )

          {:reply,
           {:needs_signature,
            %{
              request_id: request_id,
              signature_text: signature_text,
              wallet_address: wallet_address,
              panel: panel
            }}, updated_state}
      end
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:complete_join_signature, current_human, request_id, signature}, _from, state) do
    with {:ok, ready_state} <- require_ready(state),
         {:ok, wallet_address} <- fetch_wallet_address(current_human),
         :ok <- validate_pending_signature(ready_state, request_id, wallet_address, :join),
         {:ok, client} <- fetch_cached_client(ready_state, wallet_address),
         identifier = wallet_identifier(wallet_address),
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, request_id, signer),
         {:ok, registered_client} <- Clients.register(client),
         false <- room_full?(ready_state) do
      next_state =
        ready_state
        |> put_in([:clients_by_wallet, wallet_address], registered_client)
        |> update_in([:pending_signatures], &Map.delete(&1, request_id))

      {:ok, panel, updated_state} =
        invite_joined_member(next_state, registered_client, current_human)

      {:reply, {:ok, panel}, updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_public_message, current_human, body}, _from, state) do
    body = normalize_body(body)

    with {:ok, ready_state} <- require_ready(state),
         {:ok, wallet_address} <- fetch_wallet_address(current_human),
         :ok <- validate_body(body),
         :ok <- require_joined(ready_state, wallet_address),
         {:ok, client, next_state} <- ensure_registered_client(ready_state, wallet_address),
         {:ok, room} <- Conversations.get_by_id(client, ready_state.public_room.id),
         {:ok, message_id} <- Messages.send_text(room, body),
         {:ok, message} <- fetch_message(client, message_id) do
      logged_state =
        next_state
        |> persist_streamed_message(message)
        |> touch_membership_presence(wallet_address, client.inbox_id)

      updated_state = logged_state
      {:reply, {:ok, build_panel(updated_state, current_human)}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:invite_user, actor, target_wallet_or_inbox}, _from, state) do
    with {:ok, ready_state} <- require_ready(state),
         :ok <- authorize_invite(actor),
         {:ok, wallet_address, current_human} <-
           resolve_invite_target(actor, target_wallet_or_inbox),
         false <- room_full?(ready_state),
         {:ok, client, next_state} <- ensure_registered_client(ready_state, wallet_address),
         {:ok, panel, updated_state} <- invite_joined_member(next_state, client, current_human) do
      {:reply, {:ok, panel}, updated_state}
    else
      true -> {:reply, {:error, :room_full}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:kick_user, actor, target_wallet_or_inbox}, _from, state) do
    with {:ok, ready_state} <- require_ready(state),
         :ok <- authorize_kick(actor),
         {:ok, target} <- resolve_target_member(ready_state, target_wallet_or_inbox),
         {:ok, updated_state} <-
           remove_member(ready_state, target.wallet_address, target.inbox_id) do
      broadcast_refresh!()
      {:reply, {:ok, build_panel(updated_state, actor_human(actor))}, updated_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:moderator_delete_message, current_human, message_id}, _from, state) do
    with {:ok, ready_state} <- require_ready(state),
         {:ok, moderator_wallet} <- fetch_moderator_wallet(current_human),
         {:ok, _entry} <- tombstone_room_message(ready_state, message_id, moderator_wallet) do
      broadcast_refresh!()
      {:reply, {:ok, build_panel(ready_state, current_human)}, ready_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:bootstrap_room, opts}, _from, state) do
    reuse? = Keyword.get(opts, :reuse, false)

    case bootstrap_room(reuse?) do
      {:ok, room_info} ->
        :ok = XmtpElixirSdk.Runtime.reset!(@runtime_name)
        next_state = restore_state!()
        remember_relay_client(next_state)
        {:reply, {:ok, room_info}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:reset_for_test, _from, _state) do
    Repo.delete_all(MessageLog)
    Repo.delete_all(RoomMembership)
    Repo.delete_all(Room)
    :ok = XmtpElixirSdk.Runtime.reset!(@runtime_name)
    next_state = restore_state!()
    remember_relay_client(next_state)
    {:reply, :ok, next_state}
  end

  @impl true
  def handle_cast({:heartbeat, current_human}, state) do
    next_state =
      with {:ok, ready_state} <- require_ready(state),
           {:ok, wallet_address} <- fetch_wallet_address(current_human),
           {:ok, client, updated_state} <- ensure_registered_client(ready_state, wallet_address),
           :ok <- require_joined(updated_state, wallet_address) do
        touch_membership_presence(updated_state, wallet_address, client.inbox_id)
      else
        _ -> state
      end

    {:noreply, next_state}
  end

  @impl true
  def handle_info(:presence_tick, state) do
    next_state =
      case require_ready(state) do
        {:ok, ready_state} -> expire_stale_memberships(ready_state)
        {:error, _} -> state
      end

    schedule_presence_tick()
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, %Events.MessageCreated{message: message}}, state) do
    next_state =
      case require_ready(state) do
        {:ok, ready_state} ->
          if message.conversation_id == ready_state.public_room.id do
            persist_streamed_message(ready_state, message)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    broadcast_refresh!()
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, %Events.ConversationUpdated{conversation: conversation}}, state) do
    next_state =
      case require_ready(state) do
        {:ok, ready_state} ->
          if conversation.id == ready_state.public_room.id do
            public_room =
              XmtpElixirSdk.Conversation.from_record(ready_state.relay_client, conversation)

            persist_room_snapshot(%{ready_state | public_room: public_room}, public_room)
          else
            ready_state
          end

        {:error, _} ->
          state
      end

    broadcast_refresh!()
    {:noreply, next_state}
  end

  def handle_info({:xmtp, _topic, _event}, state) do
    broadcast_refresh!()
    {:noreply, state}
  end

  defp restore_state! do
    case restore_state() do
      {:ok, state} -> state
      {:error, :agent_private_key_missing} -> unavailable_state(:room_unavailable)
      {:error, :room_not_bootstrapped} -> unavailable_state(:room_unavailable)
      {:error, reason} -> raise "Autolaunch XMTP agent failed to start: #{inspect(reason)}"
    end
  end

  defp restore_state do
    with {:ok, private_key} <- configured_private_key(),
         %Room{} = room <- load_room(),
         {:ok, configured_wallet} <- Wallet.wallet_address(private_key),
         true <-
           configured_wallet == String.downcase(room.agent_wallet_address) or
             {:error, :agent_wallet_mismatch},
         :ok <- XmtpElixirSdk.Runtime.reset!(@runtime_name),
         {:ok, relay_client} <- build_registered_client(private_key),
         true <- relay_client.inbox_id == room.agent_inbox_id or {:error, :agent_inbox_mismatch},
         {:ok, runtime_room} <- import_room_snapshot(relay_client, room),
         :ok <- subscribe_room(runtime_room.id) do
      {:ok,
       %{
         mode: :ready,
         unavailable_reason: nil,
         relay_client: relay_client,
         public_room: runtime_room,
         room: room,
         clients_by_wallet: %{},
         pending_signatures: %{}
       }}
    else
      nil -> {:error, :room_not_bootstrapped}
      false -> {:error, :agent_wallet_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bootstrap_room(reuse?) do
    with {:ok, private_key} <- configured_private_key(),
         {:ok, agent_wallet} <- Wallet.wallet_address(private_key) do
      case load_room() do
        %Room{} = room when reuse? ->
          {:ok,
           %{
             room_key: room.room_key,
             conversation_id: room.conversation_id,
             agent_wallet_address: room.agent_wallet_address,
             agent_inbox_id: room.agent_inbox_id
           }}

        %Room{} ->
          {:error, :room_already_bootstrapped}

        nil ->
          :ok = XmtpElixirSdk.Runtime.reset!(@runtime_name)

          with {:ok, relay_client} <- build_registered_client(private_key),
               {:ok, room} <-
                 Conversations.create_group_optimistic(relay_client, @public_room_options),
               {:ok, _room_record} <-
                 persist_bootstrapped_room(room, agent_wallet, relay_client.inbox_id) do
            {:ok,
             %{
               room_key: Xmtp.room_key(),
               conversation_id: room.id,
               agent_wallet_address: agent_wallet,
               agent_inbox_id: relay_client.inbox_id
             }}
          end
      end
    end
  end

  defp persist_bootstrapped_room(%Conversation{} = room, agent_wallet, agent_inbox_id) do
    attrs = %{
      room_key: Xmtp.room_key(),
      conversation_id: room.id,
      agent_wallet_address: agent_wallet,
      agent_inbox_id: agent_inbox_id,
      status: "active",
      capacity: room_capacity(),
      room_name: room.name || @public_room_options.name,
      description: room.description || @public_room_options.description,
      app_data: room.app_data || @public_room_options.app_data,
      created_at_ns: room.created_at_ns,
      last_activity_ns: room.last_activity_ns,
      snapshot: room_snapshot(room)
    }

    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  defp import_room_snapshot(relay_client, %Room{} = room) do
    conversation = build_runtime_conversation(relay_client, room, list_joined_memberships(room))
    :ok = ConversationServer.import_conversations(@runtime_name, [conversation])
    Conversations.get_by_id(relay_client, room.conversation_id)
  end

  defp build_runtime_conversation(relay_client, %Room{} = room, memberships) do
    members = [agent_member(relay_client) | Enum.map(memberships, &membership_to_group_member/1)]

    snapshot = room.snapshot || %{}

    metadata = %Types.ConversationMetadata{
      creator_inbox_id: room.agent_inbox_id,
      conversation_type: :group
    }

    %Types.Conversation{
      id: room.conversation_id,
      conversation_type: :group,
      created_at_ns: room.created_at_ns,
      metadata: metadata,
      added_by_inbox_id: room.agent_inbox_id,
      name: room.room_name,
      image_url: Map.get(snapshot, "image_url"),
      description: room.description || "",
      app_data: room.app_data || "",
      permissions: Types.default_permissions(),
      consent_state: :allowed,
      disappearing_settings: nil,
      paused_for_version: nil,
      pending_removal: false,
      last_activity_ns: room.last_activity_ns,
      members: Enum.uniq_by(members, & &1.inbox_id),
      admins: [room.agent_inbox_id],
      super_admins: [room.agent_inbox_id],
      hmac_keys: [],
      last_read_times: [],
      messages: []
    }
  end

  defp agent_member(relay_client) do
    %Types.GroupMember{
      inbox_id: relay_client.inbox_id,
      account_identifiers: [relay_client.identifier.identifier],
      installation_ids: [relay_client.installation_id],
      permission_level: :admin,
      consent_state: :allowed
    }
  end

  defp membership_to_group_member(%RoomMembership{} = membership) do
    %Types.GroupMember{
      inbox_id: membership.inbox_id,
      account_identifiers: [membership.wallet_address],
      installation_ids: [],
      permission_level: :member,
      consent_state: :allowed
    }
  end

  defp build_registered_client(private_key) do
    with {:ok, wallet_address} <- Wallet.wallet_address(private_key),
         identifier = wallet_identifier(wallet_address),
         {:ok, client} <- Clients.build(@runtime_name, identifier, env: :dev),
         {:ok, %{signature_request_id: request_id, signature_text: signature_text}} <-
           Clients.unsafe_create_inbox_signature_text(client),
         {:ok, signature} <- Wallet.sign_personal_message(private_key, signature_text),
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, request_id, signer),
         {:ok, registered_client} <- Clients.register(client) do
      {:ok, registered_client}
    end
  end

  defp subscribe_room(room_id) do
    :ok = Events.subscribe(@runtime_name, {:messages, room_id}, self())
    :ok = Events.subscribe(@runtime_name, {:conversation, room_id}, self())
  end

  defp build_panel(state, current_human, status_override \\ nil, pending_request_id \\ nil)

  defp build_panel(%{mode: :unavailable}, current_human, status_override, pending_request_id) do
    connected_wallet = primary_wallet_address(current_human)

    %{
      room_name: @public_room_options.name,
      room_id: nil,
      connected_wallet: connected_wallet,
      ready?: false,
      joined?: false,
      can_join?: false,
      can_send?: false,
      moderator?: moderator_wallet?(connected_wallet),
      membership_state: :view_only,
      status: status_override || "The XMTP room is unavailable right now.",
      pending_signature_request_id: pending_request_id,
      member_count: 0,
      seat_count: room_capacity(),
      seats_remaining: room_capacity(),
      messages: []
    }
  end

  defp build_panel(
         %{mode: :ready, room: room} = state,
         current_human,
         status_override,
         pending_signature_request_id
       ) do
    connected_wallet = primary_wallet_address(current_human)
    membership_state = membership_state(state, connected_wallet, pending_signature_request_id)
    joined? = membership_state == :joined
    moderator? = moderator_wallet?(connected_wallet)
    ready? = connected_wallet && client_ready?(state, connected_wallet)
    seat_count = room.capacity
    member_count = human_member_count(room)
    seats_remaining = max(seat_count - member_count, 0)

    %{
      room_name: room.room_name,
      room_id: room.conversation_id,
      connected_wallet: connected_wallet,
      ready?: ready? == true,
      joined?: joined?,
      can_join?: can_join?(membership_state, connected_wallet),
      can_send?: joined?,
      moderator?: moderator?,
      membership_state: membership_state,
      status:
        status_override || default_status(membership_state, connected_wallet, seats_remaining),
      pending_signature_request_id:
        pending_signature_request_id || pending_request_id_for_wallet(state, connected_wallet),
      member_count: member_count,
      seat_count: seat_count,
      seats_remaining: seats_remaining,
      messages: list_panel_messages(room, connected_wallet, moderator?)
    }
  end

  defp list_panel_messages(room, connected_wallet, moderator?) do
    room
    |> Log.list_messages()
    |> Enum.reject(&membership_change_message?/1)
    |> Enum.take(-@message_limit)
    |> Enum.map(fn message ->
      sender_wallet = normalize_wallet(message.sender_wallet)
      moderated? = message.website_visibility_state == "moderator_deleted"

      %{
        key: message.xmtp_message_id,
        author: author_label(sender_wallet, message.sender_inbox_id),
        body: Log.website_body(message),
        stamp: format_stamp(message.sent_at),
        side: if(connected_wallet && sender_wallet == connected_wallet, do: :self, else: :other),
        sender_inbox_id: message.sender_inbox_id,
        sender_wallet: sender_wallet,
        website_state: if(moderated?, do: :moderator_deleted, else: :visible),
        can_delete?: moderator? and not moderated?,
        can_kick?: moderator? and sender_wallet != nil and sender_wallet != connected_wallet
      }
    end)
  end

  defp membership_change_message?(%MessageLog{message_snapshot: %{"kind" => :membership_change}}),
    do: true

  defp membership_change_message?(%MessageLog{
         message_snapshot: %{"content_type_id" => "groupUpdated"}
       }), do: true

  defp membership_change_message?(%MessageLog{message_snapshot: %{"content_type_id" => type_id}}),
    do: type_id == "groupUpdated"

  defp membership_change_message?(%MessageLog{}), do: false

  defp membership_state(_state, nil, _pending_request_id), do: :view_only

  defp membership_state(state, wallet_address, pending_request_id) do
    cond do
      joined?(state, wallet_address) ->
        :joined

      is_binary(pending_request_id) or pending_request_id_for_wallet(state, wallet_address) ->
        :join_pending_signature

      kicked?(state, wallet_address) ->
        :kicked

      room_full?(state) ->
        :full

      true ->
        :view_only
    end
  end

  defp can_join?(:view_only, connected_wallet) when is_binary(connected_wallet), do: true
  defp can_join?(:kicked, connected_wallet) when is_binary(connected_wallet), do: true
  defp can_join?(_, _), do: false

  defp default_status(:view_only, nil, _seats_remaining) do
    "Connect your Privy wallet to watch from the site and request a private-room seat."
  end

  defp default_status(:view_only, wallet_address, seats_remaining) do
    "Connected as #{short_identifier(wallet_address)}. #{seats_remaining} private-room seats remain."
  end

  defp default_status(:join_pending_signature, _wallet_address, _seats_remaining) do
    "Sign the XMTP identity message to enter the private room."
  end

  defp default_status(:joined, wallet_address, _seats_remaining) do
    "Connected as #{short_identifier(wallet_address)}. You are inside the private XMTP room."
  end

  defp default_status(:full, _wallet_address, _seats_remaining) do
    "The private room is full right now. The website stays view-only until a seat opens."
  end

  defp default_status(:kicked, _wallet_address, seats_remaining) do
    "You were removed from the private room. Click join again when you want back in. #{seats_remaining} seats are currently open."
  end

  defp persist_streamed_message(%{room: room} = state, message) do
    sender_wallet =
      case normalize_wallet(fetch_wallet_for_inbox(state, message.sender_inbox_id)) do
        nil -> nil
        wallet -> wallet
      end

    _ = Log.append_message(room, message, sender_wallet)

    updated_room =
      room
      |> Room.changeset(%{last_activity_ns: message.sent_at_ns})
      |> Repo.update!()

    %{state | room: updated_room}
  end

  defp fetch_message(client, message_id) do
    case Messages.get_by_id(client, message_id) do
      {:ok, %Types.Message{} = message} -> {:ok, message}
      {:ok, nil} -> {:error, :message_not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp persist_room_snapshot(%{room: room} = state, %{id: _conversation_id} = conversation) do
    updated_room =
      room
      |> Room.changeset(%{
        room_name: Map.get(conversation, :name),
        description: Map.get(conversation, :description),
        app_data: Map.get(conversation, :app_data),
        last_activity_ns: Map.get(conversation, :last_activity_ns),
        snapshot: room_snapshot(conversation)
      })
      |> Repo.update!()

    %{state | room: updated_room, public_room: conversation}
  end

  defp room_snapshot(%{id: _conversation_id} = conversation) do
    %{
      name: Map.get(conversation, :name),
      description: Map.get(conversation, :description),
      app_data: Map.get(conversation, :app_data),
      created_at_ns: Map.get(conversation, :created_at_ns),
      last_activity_ns: Map.get(conversation, :last_activity_ns),
      image_url: Map.get(conversation, :image_url),
      added_by_inbox_id: Map.get(conversation, :added_by_inbox_id)
    }
  end

  defp invite_joined_member(%{public_room: public_room} = state, client, current_human) do
    with {:ok, updated_room} <- Groups.add_members(public_room, [client.inbox_id]),
         {:ok, membership} <-
           upsert_membership(
             state.room,
             wallet_identifier_value(client),
             client.inbox_id,
             "joined"
           ),
         next_state <-
           state
           |> Map.put(:public_room, updated_room)
           |> Map.put(:room, Repo.preload(state.room, :memberships, force: true))
           |> put_in([:clients_by_wallet, wallet_identifier_value(client)], client)
           |> touch_membership_presence(wallet_identifier_value(client), client.inbox_id)
           |> persist_room_snapshot(updated_room) do
      _ = membership
      broadcast_refresh!()
      {:ok, build_panel(next_state, current_human), next_state}
    end
  end

  defp remove_member(state, wallet_address, inbox_id) do
    if Enum.any?(state.public_room.members, &(&1.inbox_id == inbox_id)) do
      with {:ok, updated_room} <- Groups.remove_members(state.public_room, [inbox_id]),
           {:ok, _membership} <- upsert_membership(state.room, wallet_address, inbox_id, "kicked") do
        next_state =
          state
          |> Map.put(:public_room, updated_room)
          |> Map.put(:room, Repo.preload(state.room, :memberships, force: true))
          |> persist_room_snapshot(updated_room)

        {:ok, next_state}
      end
    else
      {:error, :member_not_found}
    end
  end

  defp require_joined(state, wallet_address) do
    cond do
      joined?(state, wallet_address) -> :ok
      kicked?(state, wallet_address) -> {:error, :kicked}
      room_full?(state) -> {:error, :room_full}
      true -> {:error, :join_required}
    end
  end

  defp ensure_join_candidate(state, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} ->
        {:ok, client, state}

      :error ->
        if existing_membership?(state.room, wallet_address) do
          with {:ok, client} <-
                 Clients.create(@runtime_name, wallet_identifier(wallet_address), env: :dev) do
            {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
          end
        else
          with {:ok, client} <-
                 Clients.build(@runtime_name, wallet_identifier(wallet_address), env: :dev) do
            {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
          end
        end
    end
  end

  defp ensure_registered_client(state, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, %Client{ready?: true} = client} ->
        {:ok, client, state}

      {:ok, _client} ->
        with {:ok, client} <-
               Clients.create(@runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end

      :error ->
        with {:ok, client} <-
               Clients.create(@runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end
    end
  end

  defp fetch_cached_client(state, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :join_required}
    end
  end

  defp fetch_wallet_address(%HumanUser{} = human),
    do: fetch_wallet_address(Map.from_struct(human))

  defp fetch_wallet_address(%{} = human) do
    case primary_wallet_address(human) do
      nil -> {:error, :wallet_required}
      wallet_address -> {:ok, wallet_address}
    end
  end

  defp fetch_wallet_address(_human), do: {:error, :wallet_required}

  defp fetch_moderator_wallet(current_human) do
    with {:ok, wallet_address} <- fetch_wallet_address(current_human),
         true <- moderator_wallet?(wallet_address) do
      {:ok, wallet_address}
    else
      false -> {:error, :moderator_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_invite(:system), do: :ok
  defp authorize_invite(%HumanUser{}), do: :ok
  defp authorize_invite(%{}), do: :ok
  defp authorize_invite(_), do: {:error, :wallet_required}

  defp authorize_kick(:system), do: :ok

  defp authorize_kick(actor),
    do:
      fetch_moderator_wallet(actor)
      |> then(fn result -> if match?({:ok, _}, result), do: :ok, else: result end)

  defp resolve_invite_target(%HumanUser{} = human, _target) do
    with {:ok, wallet} <- fetch_wallet_address(human) do
      {:ok, wallet, human}
    end
  end

  defp resolve_invite_target(%{} = human, _target) do
    with {:ok, wallet} <- fetch_wallet_address(human) do
      {:ok, wallet, human}
    end
  end

  defp resolve_invite_target(:system, target_wallet_or_inbox)
       when is_binary(target_wallet_or_inbox) do
    normalized = normalize_target(target_wallet_or_inbox)

    case Repo.get_by(RoomMembership, room_id: load_room_id(), wallet_address: normalized) do
      %RoomMembership{wallet_address: wallet_address} -> {:ok, wallet_address, nil}
      nil -> {:error, :wallet_required}
    end
  end

  defp resolve_invite_target(_actor, _target), do: {:error, :wallet_required}

  defp resolve_target_member(%{room: room}, target_wallet_or_inbox)
       when is_binary(target_wallet_or_inbox) do
    normalized = normalize_target(target_wallet_or_inbox)

    by_wallet = Repo.get_by(RoomMembership, room_id: room.id, wallet_address: normalized)
    by_inbox = Repo.get_by(RoomMembership, room_id: room.id, inbox_id: normalized)

    case by_wallet || by_inbox do
      %RoomMembership{} = membership ->
        {:ok, %{wallet_address: membership.wallet_address, inbox_id: membership.inbox_id}}

      nil ->
        {:error, :member_not_found}
    end
  end

  defp resolve_target_member(_state, _target_wallet_or_inbox), do: {:error, :member_not_found}

  defp validate_pending_signature(state, request_id, wallet_address, action) do
    case Map.get(state.pending_signatures, request_id) do
      %{wallet_address: ^wallet_address, action: ^action} -> :ok
      _ -> {:error, :signature_request_missing}
    end
  end

  defp tombstone_room_message(%{room: room}, message_id, moderator_wallet) do
    case Log.tombstone_message(room, message_id, moderator_wallet) do
      {:ok, entry} -> {:ok, entry}
      {:error, :message_not_found} -> {:error, :message_not_found}
      {:error, _changeset} -> {:error, :message_not_found}
    end
  end

  defp room_full?(%{room: room}), do: human_member_count(room) >= room.capacity

  defp human_member_count(%Room{} = room) do
    room
    |> list_joined_memberships()
    |> length()
  end

  defp joined?(%{room: room}, wallet_address) do
    case Repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "joined"} -> true
      _ -> false
    end
  end

  defp existing_membership?(%Room{} = room, wallet_address) do
    not is_nil(
      Repo.get_by(RoomMembership,
        room_id: room.id,
        wallet_address: normalize_wallet(wallet_address)
      )
    )
  end

  defp kicked?(%{room: room}, wallet_address) do
    case Repo.get_by(RoomMembership,
           room_id: room.id,
           wallet_address: normalize_wallet(wallet_address)
         ) do
      %RoomMembership{membership_state: "kicked"} -> true
      _ -> false
    end
  end

  defp client_ready?(state, wallet_address) do
    case Map.get(state.clients_by_wallet, wallet_address) do
      %Client{ready?: ready?} -> ready?
      _ -> existing_membership?(state.room, wallet_address)
    end
  end

  defp pending_request_id_for_wallet(_state, nil), do: nil

  defp pending_request_id_for_wallet(state, wallet_address) do
    Enum.find_value(state.pending_signatures, fn {request_id, pending} ->
      if pending.wallet_address == wallet_address, do: request_id, else: nil
    end)
  end

  defp upsert_membership(%Room{} = room, wallet_address, inbox_id, membership_state) do
    attrs = %{
      room_id: room.id,
      wallet_address: normalize_wallet(wallet_address),
      inbox_id: inbox_id,
      membership_state: membership_state,
      last_seen_at: DateTime.utc_now()
    }

    existing = Repo.get_by(RoomMembership, room_id: room.id, wallet_address: attrs.wallet_address)

    case existing do
      nil ->
        %RoomMembership{}
        |> RoomMembership.changeset(attrs)
        |> Repo.insert()

      membership ->
        membership
        |> RoomMembership.changeset(attrs)
        |> Repo.update()
    end
  end

  defp touch_membership_presence(%{room: room} = state, wallet_address, inbox_id) do
    _ = upsert_membership(room, wallet_address, inbox_id, "joined")
    %{state | room: Repo.preload(room, :memberships, force: true)}
  end

  defp expire_stale_memberships(%{room: room} = state) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-div(presence_timeout_ms(), 1_000), :second)

    stale_memberships =
      RoomMembership
      |> where([membership], membership.room_id == ^room.id)
      |> where([membership], membership.membership_state == "joined")
      |> where(
        [membership],
        not is_nil(membership.last_seen_at) and membership.last_seen_at <= ^cutoff
      )
      |> Repo.all()

    Enum.reduce(stale_memberships, state, fn membership, acc ->
      case remove_member(acc, membership.wallet_address, membership.inbox_id) do
        {:ok, updated_state} ->
          broadcast_refresh!()
          updated_state

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp list_joined_memberships(%Room{id: room_id}) do
    RoomMembership
    |> where([membership], membership.room_id == ^room_id)
    |> where([membership], membership.membership_state == "joined")
    |> order_by([membership], asc: membership.inserted_at)
    |> Repo.all()
  end

  defp fetch_wallet_for_inbox(%{room: room}, inbox_id) do
    case Repo.get_by(RoomMembership, room_id: room.id, inbox_id: inbox_id) do
      %RoomMembership{wallet_address: wallet_address} -> wallet_address
      nil -> fetch_wallet_from_preferences(inbox_id)
    end
  end

  defp fetch_wallet_from_preferences(inbox_id) do
    case Process.get(:autolaunch_xmtp_relay_client) do
      %Client{} = relay_client ->
        case Preferences.get_inbox_states(relay_client, [inbox_id]) do
          {:ok, [inbox_state | _]} ->
            wallet_from_inbox_state(inbox_state)

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp wallet_from_inbox_state(%Types.InboxState{account_identifiers: identifiers}) do
    identifiers
    |> Enum.find_value(fn
      %Types.Identifier{identifier_kind: :ethereum, identifier: identifier} ->
        normalize_wallet(identifier)

      _ ->
        nil
    end)
  end

  defp primary_wallet_address(%{} = human) do
    [
      Map.get(human, :wallet_address) || Map.get(human, "wallet_address")
      | List.wrap(Map.get(human, :wallet_addresses) || Map.get(human, "wallet_addresses"))
    ]
    |> Enum.find_value(&normalize_wallet/1)
  end

  defp primary_wallet_address(_human), do: nil

  defp author_label(nil, inbox_id), do: short_identifier(inbox_id)
  defp author_label(wallet_address, _inbox_id), do: short_identifier(wallet_address)

  defp format_stamp(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d %H:%M")

  defp normalize_wallet(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      wallet -> String.downcase(wallet)
    end
  end

  defp normalize_wallet(_value), do: nil

  defp short_identifier(nil), do: "guest"

  defp short_identifier(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.length(trimmed) <= 12 do
      trimmed
    else
      "#{String.slice(trimmed, 0, 6)}...#{String.slice(trimmed, -4, 4)}"
    end
  end

  defp normalize_body(body) when is_binary(body), do: String.trim(body)
  defp normalize_body(_body), do: ""

  defp validate_body(""), do: {:error, :message_required}
  defp validate_body(body) when byte_size(body) > 2_000, do: {:error, :message_too_long}
  defp validate_body(_body), do: :ok

  defp normalize_target(value) when is_binary(value),
    do: value |> String.trim() |> String.downcase()

  defp wallet_identifier(wallet_address) do
    %Types.Identifier{
      identifier: normalize_wallet(wallet_address),
      identifier_kind: :ethereum
    }
  end

  defp wallet_identifier_value(%Client{identifier: %Types.Identifier{identifier: identifier}}) do
    normalize_wallet(identifier)
  end

  defp moderator_wallet?(nil), do: false

  defp moderator_wallet?(wallet_address) do
    normalize_wallet(wallet_address) in moderator_wallets()
  end

  defp moderator_wallets do
    :autolaunch
    |> Application.get_env(Xmtp, [])
    |> Keyword.get(:moderator_wallets, [])
    |> Enum.map(&String.downcase/1)
  end

  defp configured_private_key do
    :autolaunch
    |> Application.get_env(Xmtp, [])
    |> Keyword.get(:agent_private_key)
    |> Wallet.normalize_private_key()
  end

  defp room_capacity do
    :autolaunch
    |> Application.get_env(Xmtp, [])
    |> Keyword.get(:room_capacity, @default_room_capacity)
  end

  defp presence_timeout_ms do
    :autolaunch
    |> Application.get_env(Xmtp, [])
    |> Keyword.get(:presence_timeout_ms, @default_presence_timeout_ms)
  end

  defp presence_check_interval_ms do
    :autolaunch
    |> Application.get_env(Xmtp, [])
    |> Keyword.get(:presence_check_interval_ms, @default_presence_check_ms)
  end

  defp schedule_presence_tick do
    Process.send_after(self(), :presence_tick, presence_check_interval_ms())
  end

  defp load_room do
    Room
    |> Repo.get_by(room_key: Xmtp.room_key())
    |> case do
      nil -> nil
      room -> Repo.preload(room, [:memberships])
    end
  end

  defp load_room_id do
    case load_room() do
      %Room{id: room_id} -> room_id
      nil -> nil
    end
  end

  defp require_ready(%{mode: :ready} = state), do: {:ok, state}
  defp require_ready(_state), do: {:error, :room_unavailable}

  defp unavailable_state(reason) do
    %{
      mode: :unavailable,
      unavailable_reason: reason,
      relay_client: nil,
      public_room: nil,
      room: nil,
      clients_by_wallet: %{},
      pending_signatures: %{}
    }
  end

  defp actor_human(%HumanUser{} = human), do: human
  defp actor_human(%{} = human), do: human
  defp actor_human(_), do: nil

  defp broadcast_refresh! do
    Phoenix.PubSub.broadcast(
      Autolaunch.PubSub,
      Xmtp.pubsub_topic(),
      {:xmtp_public_room, :refresh}
    )
  end

  defp remember_relay_client(%{relay_client: %Client{} = relay_client}) do
    Process.put(:autolaunch_xmtp_relay_client, relay_client)
  end

  defp remember_relay_client(_state) do
    Process.delete(:autolaunch_xmtp_relay_client)
  end
end
