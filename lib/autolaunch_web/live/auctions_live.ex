defmodule AutolaunchWeb.AuctionsLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Launch
  alias AutolaunchWeb.LaunchComponents
  alias AutolaunchWeb.Live.Refreshable

  @poll_ms 15_000
  @default_filters %{"mode" => "biddable", "sort" => "newest"}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> assign(:page_title, "Tokens")
     |> assign(:active_view, "auctions")
     |> assign(:filters, @default_filters)
     |> assign_directory(@default_filters)}
  end

  def handle_event("filters_changed", %{"filters" => filters}, socket) do
    merged = Map.merge(socket.assigns.filters, filters)

    {:noreply,
     socket
     |> assign(:filters, merged)
     |> assign_directory(merged)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_directory/1)}
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <section id="auctions-intro" class="al-panel al-directory-intro" phx-hook="MissionMotion">
        <div class="al-directory-copy">
          <p class="al-kicker">Auctions</p>
          <h2>Choose an agent, inspect the live price, then open the bid view.</h2>
          <p class="al-subcopy">
            The directory is here to help you decide where to look next, not to teach every rule
            again. Each card answers three questions quickly: is it still biddable, what is the
            live price, and where do you go next?
          </p>
          <div class="al-hero-actions">
            <.link navigate={~p"/how-auctions-work"} class="al-cta-link">
              How auctions work
            </.link>
            <.link navigate={~p"/auction-returns"} class="al-ghost">
              Auction returns
            </.link>
          </div>
        </div>

        <div class="al-directory-summary">
          <div class="al-launch-tags" aria-label="Directory summary">
            <span class="al-launch-tag">Biddable {@biddable_count}</span>
            <span class="al-launch-tag">Live {@live_count}</span>
            <span class="al-launch-tag">Visible {length(@tokens)}</span>
          </div>

          <div class="al-note-grid al-directory-points">
            <article class="al-note-card">
              <span>Start simple</span>
              <strong>Budget plus max price</strong>
              <p>Open the bid view when a token looks interesting.</p>
            </article>
            <article class="al-note-card">
              <span>Minimum raise</span>
              <strong>Failed launches can return USDC</strong>
              <p>The return path stays visible after the auction ends.</p>
            </article>
            <article class="al-note-card">
              <span>Live after auction</span>
              <strong>Finished tokens move to their token page</strong>
              <p>Once the sale ends, the subject page is the better operator surface.</p>
            </article>
          </div>
        </div>
      </section>

      <section class="al-panel al-filter-panel al-directory-controls">
        <form phx-change="filters_changed" class="al-directory-form">
          <div class="al-segmented" role="group" aria-label="Token phase">
            <label class={["al-segmented-option", @filters["mode"] == "biddable" && "is-active"]}>
              <input type="radio" name="filters[mode]" value="biddable" checked={@filters["mode"] == "biddable"} />
              <span>Biddable</span>
            </label>
            <label class={["al-segmented-option", @filters["mode"] == "live" && "is-active"]}>
              <input type="radio" name="filters[mode]" value="live" checked={@filters["mode"] == "live"} />
              <span>Live</span>
            </label>
          </div>

          <label>
            <span>Sort</span>
            <select name="filters[sort]">
              <option value="newest" selected={@filters["sort"] == "newest"}>Newest first</option>
              <option value="oldest" selected={@filters["sort"] == "oldest"}>Oldest first</option>
              <option value="market_cap_desc" selected={@filters["sort"] == "market_cap_desc"}>Market cap high to low</option>
              <option value="market_cap_asc" selected={@filters["sort"] == "market_cap_asc"}>Market cap low to high</option>
            </select>
          </label>
        </form>
      </section>

      <%= if @tokens == [] do %>
        <.empty_state
          title="No tokens match this directory view yet."
          body="Switch between Biddable and Live or check back after the next launch finishes its three-day auction window."
        />
      <% else %>
        <section id="auctions-grid" class="al-token-grid" phx-hook="MissionMotion">
          <article :for={token <- @tokens} id={"auction-tile-#{token.id}"} class="al-panel al-token-card">
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
              <a :if={token.uniswap_url} href={token.uniswap_url} class="al-ghost" target="_blank" rel="noreferrer">
                Uniswap
              </a>
            </div>
          </article>
        </section>
      <% end %>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end

  defp assign_directory(socket, filters) do
    directory =
      launch_module().list_auctions(
        %{"mode" => "all", "sort" => filters["sort"]},
        socket.assigns[:current_human]
      )

    visible_tokens =
      Enum.filter(directory, fn token ->
        token.phase == Map.get(filters, "mode", "biddable")
      end)

    socket
    |> assign(:directory, directory)
    |> assign(:tokens, visible_tokens)
    |> assign(:biddable_count, Enum.count(directory, &(&1.phase == "biddable")))
    |> assign(:live_count, Enum.count(directory, &(&1.phase == "live")))
  end

  defp reload_directory(socket), do: assign_directory(socket, socket.assigns.filters)

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
    do:
      "This token is still in the active three-day auction window. The price and market cap reflect the current clearing level."

  defp directory_copy("live"),
    do:
      "This token has moved out of the auction phase. The price and market cap now follow the Uniswap market instead of the auction curve."

  defp launch_module do
    :autolaunch
    |> Application.get_env(:auctions_live, [])
    |> Keyword.get(:launch_module, Launch)
  end
end
