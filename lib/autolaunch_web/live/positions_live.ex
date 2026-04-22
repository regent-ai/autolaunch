defmodule AutolaunchWeb.PositionsLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Launch
  alias AutolaunchWeb.Live.AccountWorkspace
  alias AutolaunchWeb.Live.Refreshable

  @poll_ms 15_000

  def mount(_params, _session, socket) do
    filters = %{"status" => "", "search" => ""}
    all_positions = load_positions(socket.assigns[:current_human])

    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> assign(:page_title, "Positions")
     |> assign(:active_view, "positions")
     |> assign(:filters, filters)
     |> assign(:all_positions, all_positions)
     |> assign(:positions, filter_positions(all_positions, filters))}
  end

  def handle_event("filters_changed", %{"filters" => filters}, socket) do
    merged = Map.merge(socket.assigns.filters, filters)

    {:noreply,
     socket
     |> assign(:filters, merged)
     |> assign(:positions, filter_positions(socket.assigns.all_positions, merged))}
  end

  def handle_event("quick_filter", %{"status" => status}, socket) do
    filters = Map.put(socket.assigns.filters, "status", status)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:positions, filter_positions(socket.assigns.all_positions, filters))}
  end

  def handle_event("wallet_tx_started", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_started(socket, message)}
  end

  def handle_event("wallet_tx_registered", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_registered(socket, message, &reload_positions/1)}
  end

  def handle_event("wallet_tx_error", %{"message" => message}, socket) do
    {:noreply, Refreshable.wallet_error(socket, message)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_positions/1)}
  end

  def render(assigns) do
    active = Enum.count(assigns.all_positions, &(&1.status == "active"))
    borderline = Enum.count(assigns.all_positions, &(&1.status == "borderline"))
    inactive = Enum.count(assigns.all_positions, &(&1.status == "inactive"))
    claimable = Enum.count(assigns.all_positions, &(&1.status == "claimable"))
    returnable = Enum.count(assigns.all_positions, &(&1.status == "returnable"))
    total = length(assigns.all_positions)

    assigns =
      assigns
      |> assign(:total_count, total)
      |> assign(:active_count, active)
      |> assign(:borderline_count, borderline)
      |> assign(:inactive_count, inactive)
      |> assign(:claimable_count, claimable)
      |> assign(:returnable_count, returnable)

    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <AccountWorkspace.styles active_tab="positions" />

      <section class="al-account-page">
        <header class="al-account-topline">
          <AccountWorkspace.tabs active_tab="positions" />

          <div :if={!is_nil(@current_human)} class="al-account-utility">
            <span class="al-account-utility-note">Live triage refreshes every {poll_seconds()}s</span>
            <.link navigate={~p"/profile"} class="al-ghost">Open profile</.link>
          </div>
        </header>

        <%= if is_nil(@current_human) do %>
          <.empty_state
            title="Sign in to inspect your bids."
            body="This workspace keeps your active bids, claims, and returns in one place."
          />
        <% else %>
          <section id="positions-overview" class="al-panel al-account-overview" phx-hook="MissionMotion">
            <AccountWorkspace.identity
              current_human={@current_human}
              eyebrow="Positions"
              title={positions_title(@current_human)}
              subtitle="Triage active bids, claims, and return paths before you open a specific auction."
            />

            <div class="al-account-summary-grid">
              <AccountWorkspace.summary_card
                title="Total"
                value={Integer.to_string(@total_count)}
                hint="Tracked positions"
                tone="blue"
              />
              <AccountWorkspace.summary_card
                title="Claimable"
                value={Integer.to_string(@claimable_count)}
                hint="Ready to withdraw"
                tone="green"
              />
              <AccountWorkspace.summary_card
                title="Active"
                value={Integer.to_string(@active_count)}
                hint="Live auctions"
                tone="amber"
              />
            </div>
          </section>

          <section id="positions-panel" class="al-panel al-account-positions-panel" phx-hook="MissionMotion">
            <div class="al-account-positions-topline">
              <div class="al-account-section-head">
                <div>
                  <p class="al-kicker">Positions triage</p>
                  <h3>Use the quick buckets first, then inspect the auction only when you need detail.</h3>
                </div>
              </div>

              <div class="al-account-metric-strip">
                <article class="al-account-metric-card">
                  <span class="al-account-summary-label">All</span>
                  <strong>{@total_count}</strong>
                  <p>Total positions</p>
                </article>
                <article class="al-account-metric-card">
                  <span class="al-account-summary-label">Claimable</span>
                  <strong>{@claimable_count}</strong>
                  <p>Ready now</p>
                </article>
                <article class="al-account-metric-card">
                  <span class="al-account-summary-label">Returns</span>
                  <strong>{@returnable_count}</strong>
                  <p>Failed raises</p>
                </article>
                <article class="al-account-metric-card">
                  <span class="al-account-summary-label">Active</span>
                  <strong>{@active_count}</strong>
                  <p>Still in market</p>
                </article>
                <article class="al-account-metric-card">
                  <span class="al-account-summary-label">Borderline</span>
                  <strong>{@borderline_count}</strong>
                  <p>Needs attention</p>
                </article>
              </div>

              <form phx-change="filters_changed" class="al-account-filter-row">
                <div class="al-account-pill-row" role="group" aria-label="Quick position filters">
                  <button
                    type="button"
                    class={["al-account-pill", @filters["status"] == "" && "is-active"]}
                    phx-click="quick_filter"
                    phx-value-status=""
                  >
                    All
                  </button>
                  <button
                    type="button"
                    class={["al-account-pill", @filters["status"] == "claimable" && "is-active"]}
                    phx-click="quick_filter"
                    phx-value-status="claimable"
                  >
                    Claimable
                  </button>
                  <button
                    type="button"
                    class={["al-account-pill", @filters["status"] == "returnable" && "is-active"]}
                    phx-click="quick_filter"
                    phx-value-status="returnable"
                  >
                    Returns
                  </button>
                  <button
                    type="button"
                    class={["al-account-pill", @filters["status"] == "active" && "is-active"]}
                    phx-click="quick_filter"
                    phx-value-status="active"
                  >
                    Active
                  </button>
                  <button
                    type="button"
                    class={["al-account-pill", @filters["status"] == "borderline" && "is-active"]}
                    phx-click="quick_filter"
                    phx-value-status="borderline"
                  >
                    Borderline
                  </button>
                </div>

                <div class="al-account-search">
                  <label class="sr-only" for="positions-search">Search positions</label>
                  <input
                    id="positions-search"
                    type="search"
                    name="filters[search]"
                    value={@filters["search"]}
                    placeholder="Search by token or auction ID"
                  />
                </div>
              </form>
            </div>

            <%= if @positions == [] do %>
              <.empty_state
                title="No bids match the current view."
                body="Clear the search or switch buckets to see more positions."
              />
            <% else %>
              <div class="al-account-table-shell">
                <table class="al-account-position-table">
                  <thead>
                    <tr>
                      <th>Token / auction</th>
                      <th>Status</th>
                      <th>Your position</th>
                      <th>Max price</th>
                      <th>Current clearing price</th>
                      <th>Next action</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={position <- @positions} id={"position-row-#{position.bid_id}"}>
                      <td>
                        <div class="al-account-position-token">
                          <strong>{position.agent_name}</strong>
                          <span class="al-account-token-meta">{position.chain}</span>
                          <span class="al-account-token-meta">
                            Auction {position.auction_id} • {position.bid_id}
                          </span>
                        </div>
                      </td>
                      <td><.status_badge status={position.status} /></td>
                      <td>
                        <div class="al-account-position-stack">
                          <strong>{position.amount}</strong>
                          <span class="al-account-token-meta">{status_copy(position.status)}</span>
                        </div>
                      </td>
                      <td>
                        <div class="al-account-position-stack">
                          <strong>{position.max_price}</strong>
                          <span class="al-account-token-meta">Bid ceiling</span>
                        </div>
                      </td>
                      <td>
                        <div class="al-account-position-stack">
                          <strong>{position.current_clearing_price}</strong>
                          <span class="al-account-token-meta">
                            Inactive above {position.inactive_above_price}
                          </span>
                        </div>
                      </td>
                      <td>
                        <div class="al-account-next-step">
                          <strong>{position.next_action_label}</strong>
                          <span class="al-account-token-meta">{status_copy(position.status)}</span>
                        </div>
                      </td>
                      <td>
                        <div class="al-account-table-actions">
                          <.link navigate={~p"/auctions/#{position.auction_id}"} class="al-ghost">
                            Inspect auction
                          </.link>
                          <.wallet_tx_button
                            :if={return_action(position)}
                            id={"positions-return-#{position.bid_id}"}
                            class="al-submit"
                            tx_request={return_action(position).tx_request}
                            register_endpoint={~p"/api/bids/#{position.bid_id}/return-usdc"}
                            pending_message="Return transaction sent. Waiting for confirmation."
                            success_message="USDC return registered."
                          >
                            Return USDC
                          </.wallet_tx_button>
                          <.wallet_tx_button
                            :if={tx_action(position, :exit) && is_nil(return_action(position))}
                            id={"positions-exit-#{position.bid_id}"}
                            class="al-ghost"
                            tx_request={tx_action(position, :exit).tx_request}
                            register_endpoint={~p"/api/bids/#{position.bid_id}/exit"}
                            pending_message="Exit transaction sent. Waiting for confirmation."
                            success_message="Bid exit registered."
                          >
                            Exit bid
                          </.wallet_tx_button>
                          <.wallet_tx_button
                            :if={tx_action(position, :claim)}
                            id={"positions-claim-#{position.bid_id}"}
                            class="al-submit"
                            tx_request={tx_action(position, :claim).tx_request}
                            register_endpoint={~p"/api/bids/#{position.bid_id}/claim"}
                            pending_message="Claim transaction sent. Waiting for confirmation."
                            success_message="Claim registered."
                          >
                            Claim tokens
                          </.wallet_tx_button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </section>
        <% end %>
      </section>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp load_positions(nil), do: []

  defp load_positions(current_human),
    do: launch_module().list_positions(current_human, %{"status" => ""})

  defp reload_positions(socket) do
    all_positions = load_positions(socket.assigns.current_human)

    assign(
      socket,
      all_positions: all_positions,
      positions: filter_positions(all_positions, socket.assigns.filters)
    )
  end

  defp filter_positions(positions, filters) do
    positions
    |> filter_by_status(filters["status"])
    |> filter_by_search(filters["search"])
  end

  defp filter_by_status(positions, nil), do: positions
  defp filter_by_status(positions, ""), do: positions

  defp filter_by_status(positions, status) do
    Enum.filter(positions, &(&1.status == status))
  end

  defp filter_by_search(positions, nil), do: positions
  defp filter_by_search(positions, ""), do: positions

  defp filter_by_search(positions, search) do
    needle = String.downcase(String.trim(search))

    Enum.filter(positions, fn position ->
      [
        position.agent_name,
        position.bid_id,
        position.auction_id,
        position.chain
      ]
      |> Enum.any?(fn value ->
        value
        |> to_string()
        |> String.downcase()
        |> String.contains?(needle)
      end)
    end)
  end

  defp status_copy("active"), do: "Active — receiving tokens at the current clearing price."
  defp status_copy("ending-soon"), do: "Ending soon — the auction is near the finish line."
  defp status_copy("borderline"), do: "Borderline — one move away from inactive."

  defp status_copy("inactive"),
    do: "Inactive — not receiving tokens at the current clearing price."

  defp status_copy("returnable"),
    do: "Returnable — this auction failed its minimum raise and your USDC can be returned."

  defp status_copy("claimable"),
    do: "Claimable — the bid is exited and purchased tokens can be claimed."

  defp status_copy("pending-claim"),
    do: "Pending claim — the auction has settled, but the claim still needs to be completed."

  defp status_copy("exited"), do: "Exited — this bid is no longer participating."
  defp status_copy("claimed"), do: "Claimed — purchased tokens have already been withdrawn."
  defp status_copy("settled"), do: "Settled — the auction outcome is finalized."
  defp status_copy(_status), do: "Monitor this position from the auction detail page."

  defp return_action(position) when is_map(position) do
    Map.get(position, :return_action)
  end

  defp tx_action(position, action) when is_map(position) do
    position
    |> Map.get(:tx_actions, %{})
    |> Map.get(action)
  end

  defp positions_title(%{display_name: display_name})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp positions_title(%{wallet_address: wallet_address}) when is_binary(wallet_address),
    do: short_wallet(wallet_address)

  defp positions_title(_), do: "Autolaunch operator"

  defp short_wallet(wallet_address) do
    "#{String.slice(wallet_address, 0, 6)}...#{String.slice(wallet_address, -4, 4)}"
  end

  defp poll_seconds, do: div(@poll_ms, 1_000)

  defp launch_module do
    :autolaunch
    |> Application.get_env(:positions_live, [])
    |> Keyword.get(:launch_module, Launch)
  end
end
