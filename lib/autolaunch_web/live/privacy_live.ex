defmodule AutolaunchWeb.PrivacyLive do
  use AutolaunchWeb, :live_view

  @sections [
    %{
      title: "1. What this policy covers",
      paragraphs: [
        "This Privacy Policy explains how Regents Labs, Inc. collects, uses, and shares information when you use autolaunch.sh and related services."
      ]
    },
    %{
      title: "2. Information we collect",
      paragraphs: [
        "We may collect information you give us directly, such as wallet addresses, form entries, support requests, and the details you submit when using launch, auction, or token-holder tools.",
        "We also collect basic usage data such as browser type, device information, IP address, page views, referral data, and cookie identifiers."
      ]
    },
    %{
      title: "3. How we use information",
      paragraphs: [
        "We use information to run the site, process requests, show your account state, authenticate you, prevent abuse, monitor performance, and respond to support requests.",
        "We also use cookies and similar tools to remember preferences, keep sessions working, and remember whether you dismissed the welcome modal."
      ]
    },
    %{
      title: "4. Cookies and analytics",
      paragraphs: [
        "The site uses cookies for essential functions and for convenience features like session state, theme preference, and the one-time welcome modal.",
        "We may use analytics to understand how the site is used. We do not use cookie data for targeted advertising."
      ]
    },
    %{
      title: "5. Sharing and service providers",
      paragraphs: [
        "We may share information with service providers that help us host, secure, analyze, or operate the site. We may also share information when required by law or to protect the site, users, or rights of others.",
        "Blockchain activity is public by design. Any onchain transaction, token balance, or contract interaction you create may be visible to others on the relevant network."
      ]
    },
    %{
      title: "6. Retention and security",
      paragraphs: [
        "We keep information for as long as needed to operate the site, comply with law, resolve disputes, and maintain records. We use administrative and technical safeguards to protect the information we hold, but no system is perfectly secure.",
        "You are responsible for the security of the wallet and browser environment you use with the site."
      ]
    },
    %{
      title: "7. Your choices and contact",
      paragraphs: [
        "You can control many cookies through your browser settings, but blocking essential cookies may break parts of the site.",
        "If you have questions about privacy or your data, contact us through the support channel listed on autolaunch.sh."
      ]
    }
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Privacy Policy")
     |> assign(:active_view, "legal")
     |> assign(:sections, @sections)}
  end

  def render(assigns) do
    ~H"""
    <.shell current_human={@current_human} active_view={@active_view}>
      <section class="al-panel al-legal-hero">
        <div>
          <p class="al-kicker">Privacy Policy</p>
          <h2>How autolaunch.sh handles data</h2>
          <p class="al-subcopy">
            Last updated April 7, 2026. This policy covers the site, the launch and auction
            workflow, and related services operated by Regents Labs, Inc.
          </p>
        </div>
      </section>

      <section class="al-legal-grid">
        <article :for={section <- @sections} class="al-panel al-legal-card">
          <h3>{section.title}</h3>
          <p :for={paragraph <- section.paragraphs}>{paragraph}</p>
        </article>
      </section>

      <section class="al-panel al-legal-footer">
        <p>
          The public nature of blockchains means some activity cannot be erased from the network.
          For questions about privacy or data, contact us through the site's support channel.
        </p>
      </section>

      <.flash_group flash={@flash} />
    </.shell>
    """
  end
end
