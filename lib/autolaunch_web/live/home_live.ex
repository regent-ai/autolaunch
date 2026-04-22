defmodule AutolaunchWeb.HomeLive do
  use AutolaunchWeb, :live_view

  alias Autolaunch.Launch
  alias AutolaunchWeb.LaunchComponents
  alias AutolaunchWeb.Live.Refreshable
  alias Decimal, as: D

  @home_live_css_path Path.expand("../../../priv/static/home-live.css", __DIR__)
  @external_resource @home_live_css_path
  @home_live_css File.read!(@home_live_css_path)

  @poll_ms 15_000

  @anchor_nav [
    %{label: "Markets", href: "#home-markets"},
    %{label: "How it works", href: "#home-how-it-works"},
    %{label: "About", href: "#home-about"}
  ]

  @agent_badges [
    %{label: "Hermes", mark: "HM", href: "/launch-via-agent"},
    %{label: "OpenClaw", mark: "OC", href: "/launch-via-agent"},
    %{label: "IronClaw", mark: "IC", href: "/launch"},
    %{label: "Codex", mark: "CX", href: "/launch"},
    %{label: "Claude", mark: "CL", href: "/launch"}
  ]

  @feature_cards [
    %{
      title: "Raise before you scale",
      body:
        "Bring your agent to market, raise USDC, and fund the next stretch before your product is live.",
      href: "/launch"
    },
    %{
      title: "Give supporters a reason to stay",
      body:
        "Claims, staking, and revenue stay close once the sale is over, so the market can keep compounding around your agent.",
      href: "/profile"
    }
  ]

  @workflow_steps [
    %{
      step: "1",
      label: "Launch path",
      title: "Raise before you scale",
      body:
        "Define your agent, set the sale rails, and prepare a reviewed launch plan before the market opens."
    },
    %{
      step: "2",
      label: "Live market",
      title: "Bid with a budget and a ceiling",
      body:
        "Each buyer chooses a total budget and the highest price they will pay, then the sale clears block by block."
    },
    %{
      step: "3",
      label: "After the sale",
      title: "Give supporters a reason to stay",
      body:
        "Come back for claims, staking, and revenue actions once the market moves from sale to ownership."
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> Refreshable.schedule(@poll_ms)
     |> assign(:page_title, "Autolaunch")
     |> assign(:active_view, "home")
     |> assign(:anchor_nav, @anchor_nav)
     |> assign(:agent_badges, @agent_badges)
     |> assign(:feature_cards, @feature_cards)
     |> assign(:workflow_steps, @workflow_steps)
     |> assign_home_market()}
  end

  def handle_info(:refresh, socket) do
    {:noreply, Refreshable.refresh(socket, @poll_ms, &reload_home/1)}
  end

  def render(assigns) do
    ~H"""
    <style><%= Phoenix.HTML.raw(home_live_css()) %></style>
    <div
      id="autolaunch-homepage"
      class="al-homepage-shell rg-app-shell rg-regent-theme-autolaunch"
      phx-hook="ShellChrome"
    >
      <div class="al-homepage-surface">
        <div class="al-homepage-glow" aria-hidden="true"></div>

        <header class="al-homepage-header">
          <.link navigate={~p"/"} class="al-homepage-brand">
            <img src={~p"/images/autolaunch-logo-large.png"} alt="Autolaunch" width="48" height="48" />
            <div>
              <p>Autolaunch</p>
              <span>Agent markets</span>
            </div>
          </.link>

          <nav class="al-homepage-nav" aria-label="Homepage">
            <a :for={item <- @anchor_nav} href={item.href}>{item.label}</a>
          </nav>

          <div class="al-homepage-header-actions">
            <.link navigate={~p"/auctions"} class="al-homepage-header-cta btn btn-primary">
              Open auctions
            </.link>
            <div class="al-homepage-identity" aria-label="Current operator">
              <span class="al-homepage-identity-dot"></span>
              <span>{identity_label(@current_human)}</span>
            </div>
          </div>
        </header>

        <main class="al-homepage-main">
          <section id="home-hero" class="al-homepage-hero" phx-hook="HomeHeroMotion">
            <div class="al-homepage-hero-copy">
              <p class="al-homepage-kicker" data-home-hero-reveal>For agents with edge</p>
              <h1 data-home-hero-reveal>Turn agent edge into runway.</h1>
              <p class="al-homepage-subcopy" data-home-hero-reveal>
                Raise capital from people who believe in the agent, keep the sale fair, and come
                back for claims, staking, and revenue once the auction closes.
              </p>

              <div class="al-homepage-hero-actions" data-home-hero-reveal>
                <.link navigate={~p"/launch"} class="al-homepage-primary btn btn-primary">
                  Open launch path
                </.link>
                <.link navigate={~p"/auctions"} class="al-homepage-secondary btn btn-outline">
                  Open auctions
                </.link>
                <.link navigate={~p"/how-auctions-work"} class="al-homepage-text-link">
                  How auctions work
                </.link>
              </div>

              <div class="al-homepage-command-block" data-home-hero-reveal>
                <p class="al-homepage-command-label">Start here</p>
                <div class="al-homepage-command-bar">
                  <span class="al-homepage-command-sigil" aria-hidden="true">$</span>
                  <code>regent autolaunch prelaunch wizard</code>
                  <button
                    type="button"
                    class="al-homepage-command-copy"
                    data-copy-value={wizard_command()}
                  >
                    Copy
                  </button>
                </div>
              </div>

              <p class="al-homepage-install-copy" data-home-hero-reveal>
                Works with the operator surfaces below
              </p>

              <div
                class="al-homepage-badge-row"
                aria-label="Agent entry points"
                data-home-hero-reveal
              >
                <.link
                  :for={badge <- @agent_badges}
                  navigate={badge.href}
                  class="al-homepage-badge badge badge-outline"
                >
                  <span class="al-homepage-badge-mark">{badge.mark}</span>
                  <span>{badge.label}</span>
                </.link>
              </div>
            </div>

            <aside class="al-homepage-market-panel" data-home-hero-reveal>
              <div class="al-homepage-market-panel-head">
                <p class="al-homepage-market-eyebrow">
                  <span class="al-homepage-market-eyebrow-dot"></span>
                  Live market
                </p>
                <div class="al-homepage-market-grid">
                  <article>
                    <span>Biddable</span>
                    <strong>{@biddable_count}</strong>
                    <p>auctions open</p>
                  </article>
                  <article>
                    <span>Live</span>
                    <strong>{@live_count}</strong>
                    <p>tokens live</p>
                  </article>
                </div>
              </div>

              <div class="al-homepage-market-value">
                <div>
                  <span>Tracked market cap</span>
                  <strong>{@tracked_market_cap}</strong>
                </div>
                <p>
                  {spotlight_copy(@spotlight_token)}
                </p>
              </div>

              <div class="al-homepage-market-curve" aria-hidden="true">
                <span :for={column <- market_curve_columns()} style={"--curve-height: #{column}%"}></span>
              </div>

              <div class="al-homepage-market-foot">
                <div>
                  <span>Market focus</span>
                  <strong>{spotlight_label(@spotlight_token)}</strong>
                </div>
                <div>
                  <span>Next step</span>
                  <strong>{spotlight_action_label(@spotlight_token)}</strong>
                </div>
              </div>
            </aside>
          </section>

          <section id="homepage-feature-row" class="al-homepage-feature-row" phx-hook="MissionMotion">
            <article
              :for={card <- @feature_cards}
              class="al-homepage-feature-card"
            >
              <div class="al-homepage-feature-icon" aria-hidden="true">
                <span>{feature_icon(card.title)}</span>
              </div>
              <div class="al-homepage-feature-copy">
                <h2>{card.title}</h2>
                <p>{card.body}</p>
              </div>
              <.link navigate={card.href} class="al-homepage-feature-arrow" aria-label={card.title}>
                →
              </.link>
            </article>
          </section>

          <section id="home-markets" class="al-homepage-section" phx-hook="MissionMotion">
            <div class="al-homepage-market-table-grid">
              <.market_table
                title="Open auctions"
                count_label="View all"
                tokens={@active_tokens}
                empty_message="No auctions are open right now."
              />

              <.market_table
                title="Post-auction tokens"
                count_label="View all"
                tokens={@past_tokens}
                empty_message="No past tokens are available yet."
              />
            </div>
          </section>

          <section id="home-how-it-works" class="al-homepage-section" phx-hook="MissionMotion">
            <div class="al-homepage-steps-grid">
              <article :for={step <- @workflow_steps} class="al-homepage-step-card">
                <div class="al-homepage-step-top">
                  <span class="al-homepage-step-number">{step.step}</span>
                  <div>
                    <p class="al-homepage-kicker">{step.label}</p>
                    <h3>{step.title}</h3>
                  </div>
                </div>
                <p>{step.body}</p>
              </article>
            </div>
          </section>

          <section id="home-about" class="al-homepage-section" phx-hook="MissionMotion">
            <div class="al-homepage-about-card">
              <div class="al-homepage-about-brand">
                <img src={~p"/images/autolaunch-logo-large.png"} alt="" width="56" height="56" />
              </div>
              <div class="al-homepage-about-copy">
                <p class="al-homepage-kicker">About</p>
                <h2>Raise first. Build longer.</h2>
                <p>
                  Start from one reviewed launch path. Use the market page to find active sales.
                  Then come back when holders need claims, staking, and revenue actions.
                </p>
              </div>

              <div class="al-homepage-about-actions">
                <.link navigate={~p"/launch"} class="al-homepage-primary btn btn-primary">
                  Open launch path
                </.link>
                <.link navigate={~p"/launch-via-agent"} class="al-homepage-secondary btn btn-outline">
                  Use an agent
                </.link>
              </div>
            </div>
          </section>
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count_label, :string, required: true
  attr :tokens, :list, required: true
  attr :empty_message, :string, required: true

  defp market_table(assigns) do
    ~H"""
    <section class="al-homepage-table-card card">
      <div class="al-homepage-table-head">
        <h3>{@title}</h3>
        <span>{@count_label}</span>
      </div>

      <div class="al-homepage-table-wrap">
        <table class="al-homepage-table table">
          <thead>
            <tr>
              <th scope="col">Agent</th>
              <th scope="col">Market cap</th>
              <th scope="col">Trust</th>
              <th scope="col">Timing</th>
              <th scope="col">Price</th>
              <th scope="col">Action</th>
            </tr>
          </thead>
          <tbody>
            <%= if @tokens == [] do %>
              <tr>
                <td colspan="6" class="al-homepage-table-empty">{@empty_message}</td>
              </tr>
            <% else %>
              <tr :for={token <- @tokens}>
                <td>
                  <div class="al-homepage-token-cell">
                    <strong>{token.agent_name}</strong>
                    <span>{token.symbol} • {token.agent_id}</span>
                  </div>
                </td>
                <td>{format_currency(token.implied_market_cap_usdc, 0)}</td>
                <td>{trust_summary(token.trust)}</td>
                <td>{market_timing_label(token)}</td>
                <td>{format_currency(token.current_price_usdc, 4)}</td>
                <td>
                  <.link navigate={primary_action_href(token)} class="al-homepage-table-link">
                    {primary_action_label(token)}
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp reload_home(socket), do: assign_home_market(socket)

  defp assign_home_market(socket) do
    directory =
      launch_module().list_auctions(
        %{"mode" => "all", "sort" => "newest"},
        socket.assigns[:current_human]
      )

    socket
    |> assign(:directory, directory)
    |> assign(:active_tokens, directory |> Enum.filter(&(&1.phase == "biddable")) |> Enum.take(5))
    |> assign(:past_tokens, directory |> Enum.filter(&(&1.phase == "live")) |> Enum.take(5))
    |> assign(:biddable_count, Enum.count(directory, &(&1.phase == "biddable")))
    |> assign(:live_count, Enum.count(directory, &(&1.phase == "live")))
    |> assign(:tracked_market_cap, tracked_market_cap(directory))
    |> assign(:spotlight_token, spotlight_token(directory))
  end

  defp wizard_command, do: "regent autolaunch prelaunch wizard"

  defp market_timing_label(%{phase: "biddable", ends_at: ends_at}),
    do: LaunchComponents.time_left_label(ends_at)

  defp market_timing_label(%{phase: "live"}), do: "Auction closed"
  defp market_timing_label(_token), do: "Check token page"

  defp primary_action_href(%{phase: "live", subject_url: subject_url, detail_url: _detail_url})
       when is_binary(subject_url),
       do: subject_url

  defp primary_action_href(%{detail_url: detail_url}), do: detail_url

  defp primary_action_label(%{phase: "biddable"}), do: "Open bid view"

  defp primary_action_label(%{phase: "live", subject_url: subject_url})
       when is_binary(subject_url), do: "Open token page"

  defp primary_action_label(%{phase: "live"}), do: "Inspect launch"
  defp primary_action_label(_token), do: "Open"

  defp tracked_market_cap(directory) do
    directory
    |> Enum.map(&parse_decimal(&1.implied_market_cap_usdc))
    |> Enum.reject(&is_nil/1)
    |> sum_decimals()
    |> case do
      nil -> "Unavailable"
      decimal -> format_currency(decimal, 0)
    end
  end

  defp spotlight_token(directory) do
    Enum.find(directory, &(&1.phase == "biddable")) || Enum.find(directory, &(&1.phase == "live"))
  end

  defp spotlight_copy(nil),
    do: "Open auctions to see the next market as soon as one is available."

  defp spotlight_copy(token) do
    "#{token.agent_name} is the clearest next stop if you want to open the market and act right away."
  end

  defp spotlight_label(nil), do: "Waiting for next market"
  defp spotlight_label(token), do: "#{token.agent_name} #{token.symbol}"

  defp spotlight_action_label(nil), do: "Open auctions"
  defp spotlight_action_label(token), do: primary_action_label(token)

  defp identity_label(nil), do: "Guest"

  defp identity_label(current_human) do
    current_human.display_name || truncate_wallet(current_human.wallet_address) || "Connected"
  end

  defp truncate_wallet(nil), do: nil

  defp truncate_wallet(wallet) when is_binary(wallet) do
    "#{String.slice(wallet, 0, 6)}...#{String.slice(wallet, -4, 4)}"
  end

  defp feature_icon("Raise before you scale"), do: "▮"
  defp feature_icon("Give supporters a reason to stay"), do: "◌"
  defp feature_icon(_title), do: "•"

  defp market_curve_columns,
    do: [6, 6, 9, 8, 7, 9, 8, 8, 9, 10, 10, 13, 16, 15, 18, 17, 17, 20, 22]

  defp trust_summary(%{ens: %{connected: true, name: name}, world: %{connected: true}})
       when is_binary(name),
       do: "#{name} • World connected"

  defp trust_summary(%{ens: %{connected: true, name: name}}) when is_binary(name), do: name
  defp trust_summary(%{world: %{connected: true, launch_count: count}}), do: "World #{count}"
  defp trust_summary(_), do: "Optional links"

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(value) when is_binary(value) do
    try do
      D.new(value)
    rescue
      _ -> nil
    end
  end

  defp parse_decimal(value) when is_integer(value), do: D.new(value)
  defp parse_decimal(%D{} = value), do: value
  defp parse_decimal(_value), do: nil

  defp sum_decimals([]), do: nil
  defp sum_decimals([first | rest]), do: Enum.reduce(rest, first, &D.add/2)

  defp format_currency(nil, _places), do: "Unavailable"

  defp format_currency(value, places) do
    case parse_decimal(value) do
      nil ->
        "Unavailable"

      decimal ->
        "$" <>
          (decimal
           |> D.round(places)
           |> decimal_to_string(places)
           |> add_delimiters())
    end
  end

  defp decimal_to_string(decimal, places) do
    string = D.to_string(decimal, :normal)

    case String.split(string, ".", parts: 2) do
      [whole, fraction] ->
        padded =
          fraction
          |> String.pad_trailing(places, "0")
          |> String.slice(0, places)

        if places == 0, do: whole, else: whole <> "." <> padded

      [whole] ->
        if places == 0, do: whole, else: whole <> "." <> String.duplicate("0", places)
    end
  end

  defp add_delimiters("-" <> rest), do: "-" <> add_delimiters(rest)

  defp add_delimiters(value) do
    case String.split(value, ".", parts: 2) do
      [whole, fraction] -> add_delimiters_to_whole(whole) <> "." <> fraction
      [whole] -> add_delimiters_to_whole(whole)
    end
  end

  defp add_delimiters_to_whole(whole) do
    whole
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp home_live_css, do: @home_live_css

  defp launch_module do
    :autolaunch
    |> Application.get_env(:home_live, [])
    |> Keyword.get(:launch_module, Launch)
  end
end
