defmodule AutolaunchWeb.Live.AccountWorkspace do
  @moduledoc false
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: AutolaunchWeb.Endpoint,
    router: AutolaunchWeb.Router,
    statics: AutolaunchWeb.static_paths()

  @css_path Path.expand("../../../assets/css/account-live.css", __DIR__)
  @external_resource @css_path
  @account_css File.read!(@css_path)

  def styles(assigns) do
    ~H"""
    <style id="al-account-live-css"><%= Phoenix.HTML.raw(route_css()) %></style>
    """
  end

  attr :active_tab, :string, required: true

  def tabs(assigns) do
    ~H"""
    <nav class="al-account-tabs" aria-label="Account workspace">
      <.link navigate={~p"/profile"} class={["al-account-tab", @active_tab == "profile" && "is-active"]}>
        Profile
      </.link>
      <.link
        navigate={~p"/positions"}
        class={["al-account-tab", @active_tab == "positions" && "is-active"]}
      >
        Positions
      </.link>
    </nav>
    """
  end

  attr :current_human, :map, default: nil
  attr :eyebrow, :string, default: "Account workspace"
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  slot :meta

  def identity(assigns) do
    assigns =
      assigns
      |> assign(:wallet_label, wallet_label(assigns.current_human))
      |> assign(:joined_label, joined_label(assigns.current_human))
      |> assign(:initials, initials(assigns.current_human))

    ~H"""
    <section class="al-account-identity">
      <div class="al-account-avatar" aria-hidden="true">
        <span>{@initials}</span>
      </div>
      <div class="al-account-identity-copy">
        <p class="al-kicker">{@eyebrow}</p>
        <h2>{@title}</h2>
        <div class="al-account-identity-row">
          <span class="al-account-wallet">{@wallet_label}</span>
          <span :if={@current_human} class="al-account-chip">
            Joined {@joined_label}
          </span>
          {render_slot(@meta)}
        </div>
        <p class="al-account-subcopy">{@subtitle}</p>
      </div>
    </section>
    """
  end

  attr :title, :string, required: true
  attr :value, :string, required: true
  attr :hint, :string, default: nil
  attr :tone, :string, default: "blue"

  def summary_card(assigns) do
    ~H"""
    <article class={["al-account-summary-card", "is-#{@tone}"]}>
      <span class="al-account-summary-label">{@title}</span>
      <strong>{@value}</strong>
      <p :if={@hint}>{@hint}</p>
      <div class="al-account-summary-trace" aria-hidden="true">
        <span></span>
      </div>
    </article>
    """
  end

  def initials(%{display_name: display_name})
      when is_binary(display_name) and display_name != "" do
    display_name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "AL"
      letters -> letters
    end
  end

  def initials(%{wallet_address: wallet_address}) when is_binary(wallet_address) do
    wallet_address
    |> String.replace_prefix("0x", "")
    |> String.slice(0, 2)
    |> String.upcase()
  end

  def initials(_), do: "AL"

  def wallet_label(%{wallet_address: wallet_address}) when is_binary(wallet_address) do
    cond do
      String.length(wallet_address) <= 12 ->
        wallet_address

      true ->
        "#{String.slice(wallet_address, 0, 6)}...#{String.slice(wallet_address, -4, 4)}"
    end
  end

  def wallet_label(_), do: "Connect wallet"

  def joined_label(%{inserted_at: %NaiveDateTime{} = inserted_at}) do
    inserted_at
    |> NaiveDateTime.to_date()
    |> Calendar.strftime("%b %-d, %Y")
  end

  def joined_label(_), do: "recently"

  defp route_css, do: @account_css
end
