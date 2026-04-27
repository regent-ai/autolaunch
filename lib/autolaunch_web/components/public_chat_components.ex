defmodule AutolaunchWeb.PublicChatComponents do
  @moduledoc false

  use AutolaunchWeb, :html

  alias AutolaunchWeb.Format

  attr :room, :map, required: true
  attr :form, :map, required: true

  def public_chat_panel(assigns) do
    ~H"""
    <aside
      id="autolaunch-public-room"
      class="al-panel al-home-chat-panel"
      phx-hook="AutolaunchXmtpRoom"
    >
      <div class="al-home-chat-head">
        <div>
          <p class="al-kicker">Community room</p>
          <h3>Read the launch room.</h3>
          <p>Watch the room from the homepage. Join when you want to post.</p>
        </div>
        <div class="al-home-chat-badges">
          <span>{room_state_label(@room)}</span>
          <span>{Integer.to_string(@room.member_count)}/{Integer.to_string(@room.seat_count)} seats</span>
          <span>{active_member_copy(@room)}</span>
          <span :if={@room.connected_wallet}>{Format.short_wallet(@room.connected_wallet)}</span>
        </div>
      </div>

      <div class="al-home-chat-feed" data-public-chat-feed>
        <%= if @room.messages == [] do %>
          <div class="al-home-chat-empty">
            <strong>No messages yet.</strong>
            <p>Join the room, then post the first question or update.</p>
          </div>
        <% else %>
          <article
            :for={message <- @room.messages}
            id={"public-chat-message-#{message.key}"}
            class={["al-home-chat-message", message.side == :self && "is-self"]}
            data-public-chat-entry
            data-message-key={message.key}
          >
            <div class="al-home-chat-message-meta">
              <span>{sender_label(message.sender_kind)}</span>
              <span>{message.author}</span>
              <span>{message.stamp}</span>
            </div>
            <p>{message.body}</p>
          </article>
        <% end %>
      </div>

      <div class="al-home-chat-status" data-public-chat-status>
        {room_status_copy(@room)}
      </div>

      <button
        :if={@room.can_join?}
        type="button"
        class="al-home-chat-join"
        phx-click="public_chat_join"
      >
        Join room
      </button>

      <.form for={@form} id="public-chat-form" phx-submit="public_chat_send" class="al-home-chat-form">
        <label for={@form[:body].id}>Post a message</label>
        <textarea
          id={@form[:body].id}
          name={@form[:body].name}
          rows="3"
          placeholder="Ask a question or share an update."
          disabled={!@room.can_send?}
        >{Phoenix.HTML.Form.input_value(@form, :body)}</textarea>

        <div class="al-home-chat-composer-row">
          <p>{composer_copy(@room)}</p>
          <button type="submit" disabled={!@room.can_send?}>Send</button>
        </div>
      </.form>
    </aside>
    """
  end

  defp room_status_copy(%{status: message}) when is_binary(message) and message != "",
    do: message

  defp room_status_copy(%{ready?: false}), do: "This room is unavailable right now."
  defp room_status_copy(%{membership_state: :joined}), do: "You are in the room."

  defp room_status_copy(%{membership_state: :join_pending}),
    do: "Your room seat is being prepared."

  defp room_status_copy(%{membership_state: :join_pending_signature}),
    do: "Check your wallet to finish joining."

  defp room_status_copy(%{membership_state: :leave_pending}), do: "Your room seat is closing."

  defp room_status_copy(%{membership_state: :setup_required}),
    do: "Sign in with your wallet before you join this room."

  defp room_status_copy(%{membership_state: :watching, seats_remaining: seats_remaining})
       when seats_remaining > 0,
       do: "#{seats_remaining} seats are open. Join when you are ready."

  defp room_status_copy(%{seats_remaining: 0}),
    do: "All seats are filled right now. You can still read along from this page."

  defp room_status_copy(_room), do: "Read along before you join. Post once you are in."

  defp room_state_label(%{ready?: false}), do: "Offline"
  defp room_state_label(%{membership_state: :joined}), do: "In room"
  defp room_state_label(%{membership_state: :join_pending}), do: "Joining"
  defp room_state_label(%{membership_state: :join_pending_signature}), do: "Joining"
  defp room_state_label(%{membership_state: :leave_pending}), do: "Leaving"
  defp room_state_label(%{seats_remaining: 0}), do: "Full"
  defp room_state_label(%{connected_wallet: nil}), do: "Watch only"
  defp room_state_label(_room), do: "Ready"

  defp active_member_copy(%{active_member_count: 1}), do: "1 active"

  defp active_member_copy(%{active_member_count: count}) when is_integer(count),
    do: "#{count} active"

  defp active_member_copy(_room), do: "0 active"

  defp sender_label(:agent), do: "Agent"
  defp sender_label(:system), do: "System"
  defp sender_label(_kind), do: "Person"

  defp composer_copy(%{can_send?: true}),
    do: "Keep messages short so the room stays easy to follow."

  defp composer_copy(%{can_join?: true}), do: "Join the room first if you want to post."

  defp composer_copy(%{membership_state: :join_pending}),
    do: "Wait for your seat to finish opening before posting."

  defp composer_copy(%{membership_state: :join_pending_signature}),
    do: "Finish joining before posting."

  defp composer_copy(%{seats_remaining: 0}), do: "Posting is closed while the room is full."
  defp composer_copy(_room), do: "Read along here even if you are not ready to post."
end
