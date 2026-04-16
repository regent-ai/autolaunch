defmodule AutolaunchWeb.HomeLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.{Launch, Xmtp}
  alias AutolaunchWeb.Live.Refreshable
  alias AutolaunchWeb.LaunchComponents

  @poll_ms 15_000

  @home_steps [
    %{
      title: "Start the wizard",
      body: "Save the launch plan first so your agent has one clean set of inputs to work from."
    },
    %{
      title: "Run the launch",
      body:
        "Validate, publish, run, and monitor from the same path instead of bouncing between tools."
    },
    %{
      title: "Come back here live",
      body:
        "Use the site to watch active auctions, inspect token pages, and stay on the wire once the market is moving."
    }
  ]

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = Xmtp.subscribe()
    end

    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> assign(:page_title, "Autolaunch")
     |> assign(:active_view, "home")
     |> assign(:home_steps, @home_steps)
     |> assign(
       :privy_app_id,
       Keyword.get(Application.get_env(:autolaunch, :privy, []), :app_id, "")
     )
     |> assign(:xmtp_room, load_xmtp_panel(socket.assigns[:current_human]))
     |> assign_home_market()}
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_home/1)}
  end

  def handle_info({:xmtp_public_room, :refresh}, socket) do
    {:noreply, assign(socket, :xmtp_room, load_xmtp_panel(socket.assigns.current_human))}
  end

  def handle_event("xmtp_send", %{"body" => body}, socket) do
    case Xmtp.send_public_message(socket.assigns.current_human, body) do
      {:ok, panel} ->
        {:noreply, assign(socket, :xmtp_room, panel)}

      {:error, reason} ->
        {:noreply, assign(socket, :xmtp_room, xmtp_error_panel(socket.assigns, reason))}
    end
  end

  def handle_event("xmtp_join", _params, socket) do
    case Xmtp.request_join(socket.assigns.current_human) do
      {:ok, panel} ->
        {:noreply, assign(socket, :xmtp_room, panel)}

      {:needs_signature, %{request_id: request_id, signature_text: signature_text, panel: panel}} ->
        {:noreply,
         socket
         |> assign(:xmtp_room, panel)
         |> push_event("xmtp:sign-request", %{
           request_id: request_id,
           signature_text: signature_text,
           wallet_address: panel.connected_wallet
         })}

      {:error, reason} ->
        {:noreply, assign(socket, :xmtp_room, xmtp_error_panel(socket.assigns, reason))}
    end
  end

  def handle_event(
        "xmtp_join_signature_signed",
        %{"request_id" => request_id, "signature" => signature},
        socket
      ) do
    case Xmtp.complete_join_signature(socket.assigns.current_human, request_id, signature) do
      {:ok, panel} ->
        {:noreply, assign(socket, :xmtp_room, panel)}

      {:error, reason} ->
        {:noreply, assign(socket, :xmtp_room, xmtp_error_panel(socket.assigns, reason))}
    end
  end

  def handle_event("xmtp_join_signature_failed", %{"message" => message}, socket) do
    {:noreply, update(socket, :xmtp_room, &Map.put(&1, :status, message))}
  end

  def handle_event("xmtp_heartbeat", _params, socket) do
    :ok = Xmtp.heartbeat(socket.assigns.current_human)
    {:noreply, socket}
  end

  def handle_event("xmtp_delete_message", %{"message_id" => message_id}, socket) do
    case Xmtp.moderator_delete_message(socket.assigns.current_human, message_id) do
      {:ok, panel} ->
        {:noreply, assign(socket, :xmtp_room, panel)}

      {:error, reason} ->
        {:noreply, assign(socket, :xmtp_room, xmtp_error_panel(socket.assigns, reason))}
    end
  end

  def handle_event("xmtp_kick_user", %{"target" => target}, socket) do
    case Xmtp.moderator_kick_user(socket.assigns.current_human, target) do
      {:ok, panel} ->
        {:noreply, assign(socket, :xmtp_room, panel)}

      {:error, reason} ->
        {:noreply, assign(socket, :xmtp_room, xmtp_error_panel(socket.assigns, reason))}
    end
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <div id="home-page" class="al-home-layout">
        <div class="al-home-main">
          <section id="home-hero" class="al-panel al-home-hero" phx-hook="MissionMotion">
            <div class="al-home-hero-copy">
              <p class="al-kicker">Start here</p>
              <h2>Copy the wizard command. Start the launch from one clear place.</h2>
              <p class="al-subcopy">
                Start with the saved plan, run the launch in the command line, then return here when
                the auction is live and people need a next step.
              </p>

              <div class="al-hero-actions">
                <button type="button" class="al-cta-link al-cta-link--primary" data-copy-value={wizard_command()}>
                  Copy wizard command
                </button>
                <.link navigate={~p"/launch"} class="al-ghost">Open launch console</.link>
              </div>

              <div class="al-launch-tags" aria-label="Homepage facts">
                <span class="al-launch-tag">Save one plan first</span>
                <span class="al-launch-tag">Run the launch in the CLI</span>
                <span class="al-launch-tag">Watch the live auction here</span>
              </div>
              <p class="al-inline-note">
                Need operator prompts or the step-by-step launch doorway?
                <.link navigate={~p"/launch-via-agent"} class="al-inline-link">Open operator path</.link>.
              </p>
              <p class="al-inline-note">
                Need the auction model first?
                <.link navigate={~p"/how-auctions-work"} class="al-inline-link">Open the guide</.link>.
              </p>
            </div>

            <.terminal_command_panel
              kicker="Copy and paste"
              title="Wizard command"
              command={wizard_command()}
              output_label="What to run next"
              output={wizard_transcript()}
              copy_label="Copy command"
            />
          </section>

          <section id="home-market-peek" class="al-panel al-home-market-peek" phx-hook="MissionMotion">
            <div class="al-home-market-head">
              <div>
                <p class="al-kicker">Live auctions</p>
                <h3>See what is open, then jump straight to the action page.</h3>
                <p class="al-subcopy">
                  This preview is here to help you choose the next click quickly. Use the full
                  directory when you want every live market and every filter.
                </p>
              </div>

              <div class="al-home-market-actions">
                <div class="al-launch-tags" aria-label="Auction counts">
                  <span class="al-launch-tag">Biddable {@biddable_count}</span>
                  <span class="al-launch-tag">Live {@live_count}</span>
                  <span class="al-launch-tag">Showing {length(@preview_tokens)}</span>
                </div>
                <.link navigate={~p"/auctions"} class="al-submit">Open all auctions</.link>
              </div>
            </div>

            <%= if @preview_tokens == [] do %>
              <.empty_state
                title="No auctions are live yet."
                body="The next launch will appear here as soon as the market opens."
                action_label="Open the guide"
                action_href={~p"/how-auctions-work"}
              />
            <% else %>
              <section class="al-token-grid al-home-token-grid">
                <article
                  :for={token <- @preview_tokens}
                  id={"home-auction-preview-#{token.id}"}
                  class="al-panel al-token-card"
                >
                  <div class="al-token-card-head">
                    <div>
                      <p class="al-kicker">{token.agent_id}</p>
                      <h3>{token.agent_name}</h3>
                      <p class="al-inline-note">{token.symbol} • {token.phase}</p>
                    </div>
                    <span class={["al-status-badge", if(token.phase == "biddable", do: "is-ready", else: "is-muted")]}>
                      {String.capitalize(token.phase)}
                    </span>
                  </div>

                  <div class="al-launch-tags">
                    <span class="al-launch-tag">Price {display_value(token.current_price_usdc, "USDC")}</span>
                    <span class="al-launch-tag">Market cap {display_value(token.implied_market_cap_usdc, "USDC")}</span>
                    <span class="al-launch-tag">Started {format_date(token.started_at)}</span>
                  </div>

                  <div class="al-note-grid al-token-card-facts">
                    <article class="al-note-card">
                      <span>Price source</span>
                      <strong>{humanize_price_source(token.price_source)}</strong>
                      <p>{directory_copy(token.phase)}</p>
                    </article>
                    <article class="al-note-card">
                      <span>Auction</span>
                      <strong>{LaunchComponents.time_left_label(token.ends_at)}</strong>
                      <p>Trust summary: {trust_summary(token.trust)}</p>
                    </article>
                  </div>

                  <div class="al-action-row">
                    <.link navigate={token.detail_url} class="al-submit">
                      {if token.phase == "biddable", do: "Open bid view", else: "Inspect launch"}
                    </.link>
                    <.link :if={token.subject_url} navigate={token.subject_url} class="al-ghost">
                      Open token detail
                    </.link>
                  </div>
                </article>
              </section>
            <% end %>
          </section>

          <section id="home-flow" class="al-panel al-home-flow" phx-hook="MissionMotion">
            <div class="al-section-head">
              <div>
                <p class="al-kicker">What happens next</p>
                <h3>Use home as the launcher, not the whole control room.</h3>
              </div>
            </div>

            <div class="al-directory-facts-grid">
              <article :for={step <- @home_steps} class="al-directory-fact-card">
                <span>Step</span>
                <strong>{step.title}</strong>
                <p>{step.body}</p>
              </article>
            </div>
          </section>

          <details id="home-operator-tools" class="al-panel al-disclosure" phx-hook="MissionMotion">
            <summary class="al-disclosure-summary">
              <div>
                <p class="al-kicker">Operator extras</p>
                <h3>Open the launch doorway, trust tools, and live room only when you need them.</h3>
              </div>
              <span class="al-network-badge">Secondary</span>
            </summary>

            <div class="al-note-grid">
              <article class="al-note-card">
                <span>Operator prompts</span>
                <strong>OpenClaw and Hermes briefs live on the operator page.</strong>
                <p>Use the operator doorway when you want the copy-ready handoff, not when you just need to launch or bid.</p>
                <div class="al-action-row">
                  <.link navigate={~p"/launch-via-agent"} class="al-submit">Open operator path</.link>
                </div>
              </article>

              <article class="al-note-card">
                <span>Trust tools</span>
                <strong>Link identity details and start a verification from the same menu.</strong>
                <p>Open Trust Check, ENS Link, or X Link only when the launch needs those public signals.</p>
                <div class="al-action-row">
                  <.link navigate={~p"/agentbook"} class="al-ghost">Trust check</.link>
                  <.link navigate={~p"/ens-link"} class="al-ghost">ENS link</.link>
                  <.link navigate={~p"/x-link"} class="al-ghost">X link</.link>
                </div>
              </article>
            </div>

            <section
              id="home-xmtp-room"
              class="al-panel al-xmtp-room al-home-xmtp-room"
              phx-hook="PrivyXmtpRoom"
              data-privy-app-id={@privy_app_id}
              data-pending-request-id={@xmtp_room.pending_signature_request_id}
              data-connected-wallet={@xmtp_room.connected_wallet}
              data-membership-state={@xmtp_room.membership_state}
              data-can-join={to_string(@xmtp_room.can_join?)}
              data-can-send={to_string(@xmtp_room.can_send?)}
            >
              <div class="al-xmtp-head">
                <div class="al-xmtp-copy">
                  <p class="al-kicker">Live wire</p>
                  <h2>Keep the operator room close, not in the way.</h2>
                  <p class="al-subcopy">
                    Open the room when you need to follow operator chatter while the market is moving.
                  </p>
                </div>

                <div class="al-xmtp-badges">
                  <span class="al-network-badge">XMTP group</span>
                  <span class="al-network-badge">
                    {@xmtp_room.member_count}/{@xmtp_room.seat_count} private seats
                  </span>
                  <span class="al-network-badge">{length(@xmtp_room.messages)} recent</span>
                </div>
              </div>

              <div class="al-xmtp-layout">
                <div class="al-xmtp-feed" data-xmtp-feed>
                  <%= if @xmtp_room.messages == [] do %>
                    <div class="al-xmtp-empty">
                      No public posts yet. Connect your wallet and send the first one.
                    </div>
                  <% else %>
                    <%= for message <- @xmtp_room.messages do %>
                      <article
                        id={"xmtp-room-message-#{message.key}"}
                        class={["al-xmtp-bubble", message.side == :self && "is-self"]}
                        data-xmtp-entry
                        data-message-key={message.key}
                      >
                        <header>
                          <strong>{message.author}</strong>
                          <span>{message.stamp}</span>
                        </header>
                        <p>{message.body}</p>
                        <div :if={@xmtp_room.moderator?} class="al-xmtp-moderation">
                          <button
                            :if={message.can_delete?}
                            type="button"
                            class="al-ghost"
                            phx-click="xmtp_delete_message"
                            phx-value-message_id={message.key}
                          >
                            Delete on website
                          </button>
                          <button
                            :if={message.can_kick?}
                            type="button"
                            class="al-ghost"
                            phx-click="xmtp_kick_user"
                            phx-value-target={message.sender_wallet || message.sender_inbox_id}
                          >
                            Kick user
                          </button>
                        </div>
                      </article>
                    <% end %>
                  <% end %>
                </div>

                <div class="al-xmtp-composer">
                  <div class="al-xmtp-composer-head">
                    <button type="button" class="al-submit" data-xmtp-auth>
                      {if @current_human, do: "Disconnect wallet", else: "Connect wallet"}
                    </button>

                    <button
                      :if={@current_human}
                      type="button"
                      class="al-ghost"
                      data-xmtp-join
                      disabled={!@xmtp_room.can_join?}
                    >
                      Join room
                    </button>

                    <p class="al-inline-note" data-xmtp-state>{@xmtp_room.status}</p>
                  </div>

                  <label class="al-xmtp-input-wrap">
                    <span>Message</span>
                    <input
                      type="text"
                      maxlength="2000"
                      placeholder="Write to the Autolaunch wire"
                      data-xmtp-input
                      disabled={!@xmtp_room.can_send?}
                    />
                  </label>

                  <button type="button" class="al-submit" data-xmtp-send disabled={!@xmtp_room.can_send?}>
                    Send update
                  </button>
                </div>
              </div>
            </section>
          </details>
        </div>
      </div>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp reload_home(socket), do: assign_home_market(socket)

  defp assign_home_market(socket) do
    directory =
      launch_module().list_auctions(
        %{"mode" => "all", "sort" => "newest"},
        socket.assigns[:current_human]
      )

    preview_tokens =
      directory
      |> Enum.sort_by(fn token -> if token.phase == "biddable", do: 0, else: 1 end)
      |> Enum.take(4)

    socket
    |> assign(:preview_tokens, preview_tokens)
    |> assign(:biddable_count, Enum.count(directory, &(&1.phase == "biddable")))
    |> assign(:live_count, Enum.count(directory, &(&1.phase == "live")))
  end

  defp wizard_command, do: "regent autolaunch prelaunch wizard"

  defp wizard_transcript do
    """
    > regent autolaunch prelaunch validate --plan plan_alpha
    > regent autolaunch prelaunch publish --plan plan_alpha
    > regent autolaunch launch run --plan plan_alpha
    > regent autolaunch launch monitor --job job_alpha
    """
    |> String.trim()
  end

  defp display_value(nil, unit), do: "Unavailable #{unit}"
  defp display_value(value, unit), do: "#{value} #{unit}"

  defp format_date(nil), do: "Unknown"

  defp format_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%b %-d")
      _ -> "Unknown"
    end
  end

  defp humanize_price_source("auction_clearing"), do: "Auction clearing"
  defp humanize_price_source("uniswap_spot"), do: "Uniswap spot"
  defp humanize_price_source("uniswap_spot_unavailable"), do: "Quote pending"
  defp humanize_price_source(_), do: "Unavailable"

  defp trust_summary(%{ens: %{connected: true, name: name}, world: %{connected: true}})
       when is_binary(name),
       do: "#{name} • World connected"

  defp trust_summary(%{ens: %{connected: true, name: name}}) when is_binary(name), do: name
  defp trust_summary(%{world: %{connected: true, launch_count: count}}), do: "World #{count}"
  defp trust_summary(_), do: "Optional links"

  defp directory_copy("biddable"),
    do: "Still inside the active auction window."

  defp directory_copy("live"),
    do: "Now trading after the auction closed."

  defp load_xmtp_panel(current_human) do
    {:ok, panel} = Xmtp.public_room_panel(current_human)
    panel
  end

  defp xmtp_error_panel(assigns, :wallet_required) do
    Map.put(assigns.xmtp_room, :status, "Connect your wallet before joining the room.")
  end

  defp xmtp_error_panel(assigns, :message_required) do
    Map.put(assigns.xmtp_room, :status, "Write a message before sending.")
  end

  defp xmtp_error_panel(assigns, :message_too_long) do
    Map.put(assigns.xmtp_room, :status, "Messages must stay under 2,000 characters.")
  end

  defp xmtp_error_panel(assigns, :signature_request_missing) do
    Map.put(assigns.xmtp_room, :status, "The signature request expired. Click join again.")
  end

  defp xmtp_error_panel(assigns, :join_required) do
    Map.put(assigns.xmtp_room, :status, "Join the room before sending.")
  end

  defp xmtp_error_panel(assigns, :room_full) do
    Map.put(
      assigns.xmtp_room,
      :status,
      "The room is full right now. Watch from the feed until a seat opens."
    )
  end

  defp xmtp_error_panel(assigns, :kicked) do
    Map.put(
      assigns.xmtp_room,
      :status,
      "You were removed from the room. Click join again when ready."
    )
  end

  defp xmtp_error_panel(assigns, :moderator_required) do
    Map.put(assigns.xmtp_room, :status, "Only moderator wallets can manage the public mirror.")
  end

  defp xmtp_error_panel(assigns, :message_not_found) do
    Map.put(
      assigns.xmtp_room,
      :status,
      "That message is no longer available in the website mirror."
    )
  end

  defp xmtp_error_panel(assigns, :member_not_found) do
    Map.put(assigns.xmtp_room, :status, "That user is no longer inside the private room.")
  end

  defp xmtp_error_panel(assigns, _reason) do
    Map.put(assigns.xmtp_room, :status, "The room is unavailable right now.")
  end

  defp launch_module do
    :autolaunch
    |> Application.get_env(:home_live, [])
    |> Keyword.get(:launch_module, Launch)
  end
end
