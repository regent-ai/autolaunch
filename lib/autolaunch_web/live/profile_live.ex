defmodule AutolaunchWeb.ProfileLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Portfolio
  alias AutolaunchWeb.Live.AccountWorkspace
  alias AutolaunchWeb.Live.Refreshable

  @poll_ms 15_000

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> assign(:page_title, "Profile")
     |> assign(:active_view, "profile")
     |> assign(:snapshot, load_snapshot(socket.assigns[:current_human]))}
  end

  def handle_event("refresh_profile", _params, socket) do
    case socket.assigns.current_human &&
           portfolio_module().request_manual_refresh(socket.assigns.current_human) do
      {:ok, snapshot} ->
        {:noreply,
         socket |> assign(:snapshot, snapshot) |> put_flash(:info, "Profile refresh started.")}

      {:error, {:cooldown, seconds}} ->
        {:noreply,
         put_flash(socket, :error, "Wait #{seconds} more seconds before refreshing again.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Profile refresh could not start.")}
    end
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_snapshot/1)}
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <AccountWorkspace.styles active_tab="profile" />

      <section class="al-account-page">
        <header class="al-account-topline">
          <AccountWorkspace.tabs active_tab="profile" />

          <div :if={!is_nil(@current_human)} class="al-account-utility">
            <span class="al-account-utility-note">
              Last updated {format_datetime(@snapshot.refreshed_at)}
            </span>
            <button
              type="button"
              class="al-submit"
              phx-click="refresh_profile"
              disabled={refresh_disabled?(@snapshot.next_manual_refresh_at)}
            >
              {refresh_label(@snapshot.next_manual_refresh_at)}
            </button>
          </div>
        </header>

        <%= if is_nil(@current_human) do %>
          <.empty_state
            title="Sign in to see your token portfolio."
            body="This workspace is built from the wallets linked to your account."
          />
        <% else %>
          <section id="profile-overview" class="al-panel al-account-overview" phx-hook="MissionMotion">
            <AccountWorkspace.identity
              current_human={@current_human}
              eyebrow="Profile"
              title={profile_title(@current_human)}
              subtitle="Review launched tokens, staked exposure, and the next pages worth opening."
            />

            <div class="al-account-summary-grid">
              <AccountWorkspace.summary_card
                title="Launched"
                value={Integer.to_string(length(@snapshot.launched_tokens || []))}
                hint="Tokens launched"
                tone="blue"
              />
              <AccountWorkspace.summary_card
                title="Staked"
                value={Integer.to_string(length(@snapshot.staked_tokens || []))}
                hint="Tokens staked"
                tone="green"
              />
              <AccountWorkspace.summary_card
                title="Status"
                value={snapshot_status_label(@snapshot.status)}
                hint={snapshot_status_hint(@snapshot.status)}
                tone={snapshot_status_tone(@snapshot.status)}
              />
            </div>
          </section>

          <section id="profile-banner" class="al-account-banner" phx-hook="MissionMotion">
            <div class="al-account-banner-copy">
              <p class="al-kicker">Snapshot</p>
              <h3>Your launch and staking snapshot</h3>
              <p>{snapshot_copy(@snapshot.status)}</p>
            </div>

            <div class="al-account-banner-actions">
              <.link navigate={~p"/positions"} class="al-ghost">Open positions workspace</.link>
              <span class="al-account-note">
                Auto-refresh every {poll_seconds()}s
              </span>
            </div>
          </section>

          <section id="profile-sections" class="al-account-section-grid" phx-hook="MissionMotion">
            <section id="profile-launched" class="al-panel al-account-section">
              <div class="al-account-section-head">
                <div>
                  <p class="al-kicker">Launched tokens</p>
                  <h3>Tokens launched from your linked wallets.</h3>
                </div>
                <.link navigate={~p"/auctions"} class="al-account-link">Open auction view</.link>
              </div>

              <%= if (@snapshot.launched_tokens || []) == [] do %>
                <.empty_state
                  title="No launched tokens yet."
                  body="Launch a token first, then come back here to keep the market and post-launch pages close."
                />
              <% else %>
                <div class="al-account-token-list">
                  <article
                    :for={token <- @snapshot.launched_tokens}
                    class="al-account-token-row"
                  >
                    <div class="al-account-token-name">
                      <strong>{token.agent_name}</strong>
                      <span class="al-account-token-meta">{token.symbol}</span>
                    </div>

                    <div class="al-account-data-stack">
                      <.status_badge status={token.phase} />
                      <span class="al-account-data-label">Current phase</span>
                    </div>

                    <div class="al-account-data-stack">
                      <strong>{display_money(token.implied_market_cap_usdc)}</strong>
                      <span class="al-account-data-label">Market cap</span>
                    </div>

                    <div class="al-account-data-stack">
                      <strong>{display_money(token.current_price_usdc)}</strong>
                      <span class="al-account-data-label">Token price</span>
                    </div>

                    <div class="al-action-row">
                      <.link navigate={token.detail_url} class="al-ghost">Open auction view</.link>
                    </div>
                  </article>
                </div>
              <% end %>
            </section>

            <section id="profile-staked" class="al-panel al-account-section">
              <div class="al-account-section-head">
                <div>
                  <p class="al-kicker">Staked tokens</p>
                  <h3>Your active revenue positions.</h3>
                </div>
                <.link navigate={~p"/positions"} class="al-account-link">Open positions view</.link>
              </div>

              <%= if (@snapshot.staked_tokens || []) == [] do %>
                <.empty_state
                  title="No staked token positions yet."
                  body="Stake from a token page after launch if you want your ongoing exposure and claimable balance in one place."
                />
              <% else %>
                <div class="al-account-token-list">
                  <article
                    :for={token <- @snapshot.staked_tokens}
                    class="al-account-token-row"
                  >
                    <div class="al-account-token-name">
                      <strong>{token.agent_name}</strong>
                      <span class="al-account-token-meta">{token.symbol}</span>
                    </div>

                    <div class="al-account-data-stack">
                      <strong>{token.staked_token_amount}</strong>
                      <span class="al-account-data-label">Your stake</span>
                    </div>

                    <div class="al-account-data-stack">
                      <strong>{display_money(token.claimable_usdc)}</strong>
                      <span class="al-account-data-label">Claimable USDC</span>
                    </div>

                    <div class="al-account-data-stack">
                      <strong>{display_money(token.staked_usdc_value)}</strong>
                      <span class="al-account-data-label">Stake value</span>
                    </div>

                    <div class="al-action-row">
                      <.link navigate={token.detail_url} class="al-submit">Open token page</.link>
                    </div>
                  </article>
                </div>
              <% end %>
            </section>
          </section>
        <% end %>
      </section>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp load_snapshot(nil),
    do: %{
      status: "pending",
      launched_tokens: [],
      staked_tokens: [],
      refreshed_at: nil,
      next_manual_refresh_at: nil
    }

  defp load_snapshot(current_human) do
    case portfolio_module().get_snapshot(current_human) do
      {:ok, snapshot} ->
        snapshot

      _ ->
        %{
          status: "error",
          launched_tokens: [],
          staked_tokens: [],
          refreshed_at: nil,
          next_manual_refresh_at: nil
        }
    end
  end

  defp reload_snapshot(socket) do
    assign(socket, :snapshot, load_snapshot(socket.assigns.current_human))
  end

  defp refresh_disabled?(nil), do: false

  defp refresh_disabled?(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> DateTime.compare(datetime, DateTime.utc_now()) == :gt
      _ -> false
    end
  end

  defp refresh_label(nil), do: "Refresh portfolio"

  defp refresh_label(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} ->
        remaining = max(DateTime.diff(datetime, DateTime.utc_now(), :second), 0)
        if remaining > 0, do: "Refresh in #{remaining}s", else: "Refresh portfolio"

      _ ->
        "Refresh portfolio"
    end
  end

  defp format_datetime(nil), do: "not yet"

  defp format_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> Calendar.strftime(datetime, "%b %-d, %H:%M:%S UTC")
      _ -> "not yet"
    end
  end

  defp snapshot_copy("running"), do: "The snapshot is rebuilding in the background."
  defp snapshot_copy("ready"), do: "The cached snapshot is ready to browse."
  defp snapshot_copy("error"), do: "The last snapshot failed. Use refresh to try again."

  defp snapshot_copy(_),
    do: "The first snapshot will appear as soon as the background rebuild finishes."

  defp snapshot_status_label("running"), do: "Refreshing"
  defp snapshot_status_label("ready"), do: "Active"
  defp snapshot_status_label("error"), do: "Needs retry"
  defp snapshot_status_label(_), do: "Pending"

  defp snapshot_status_hint("running"), do: "Snapshot in progress"
  defp snapshot_status_hint("ready"), do: "All systems normal"
  defp snapshot_status_hint("error"), do: "Try another refresh"
  defp snapshot_status_hint(_), do: "First snapshot pending"

  defp snapshot_status_tone("running"), do: "amber"
  defp snapshot_status_tone("ready"), do: "green"
  defp snapshot_status_tone("error"), do: "slate"
  defp snapshot_status_tone(_), do: "blue"

  defp profile_title(%{display_name: display_name})
       when is_binary(display_name) and display_name != "",
       do: display_name

  defp profile_title(%{wallet_address: wallet_address}) when is_binary(wallet_address),
    do: short_wallet(wallet_address)

  defp profile_title(_), do: "Autolaunch operator"

  defp short_wallet(wallet_address) do
    "#{String.slice(wallet_address, 0, 6)}...#{String.slice(wallet_address, -4, 4)}"
  end

  defp poll_seconds, do: div(@poll_ms, 1_000)

  defp display_money(nil), do: "Unavailable"
  defp display_money(value), do: "#{value} USDC"

  defp portfolio_module do
    :autolaunch
    |> Application.get_env(:profile_live, [])
    |> Keyword.get(:portfolio_module, Portfolio)
  end
end
