import type { Hook } from "phoenix_live_view"

import { LocalStorage, Privy } from "../../vendor/privy-core.esm.js"

const PROVIDER_STORAGE_KEY = "autolaunch:privy:oauth-provider"

type PrivyUser = {
  id?: string
  email?: { address?: string }
  linked_accounts?: Array<{ type?: string; address?: string }>
} | null

function walletForUser(user: PrivyUser): string | null {
  const wallet = user?.linked_accounts?.find((account) => account?.address)
  return wallet?.address || null
}

function walletsForUser(user: PrivyUser): string[] {
  return (user?.linked_accounts || [])
    .map((account) => account?.address?.trim())
    .filter((address): address is string => Boolean(address))
}

function labelForUser(user: PrivyUser): string {
  return user?.email?.address || user?.id || "connected"
}

export const PrivyAuth: Hook = {
  async mounted() {
    const button = this.el.querySelector<HTMLElement>("[data-privy-action='toggle']")
    const state = this.el.querySelector<HTMLElement>("[data-privy-state]")
    const appId = this.el.dataset.privyAppId || ""
    const sessionState = this.el.dataset.sessionState || "missing"

    if (!button || !state || appId.trim() === "") return

    const csrfToken =
      document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content?.trim() || ""

    const privy = new Privy({ appId, clientId: appId, storage: new LocalStorage() })

    const syncSession = async (user: PrivyUser) => {
      const token = await privy.getAccessToken()
      if (!token) return false

      const response = await fetch("/api/auth/privy/session", {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
          ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
        },
        credentials: "same-origin",
        body: JSON.stringify({
          display_name: labelForUser(user),
          wallet_address: walletForUser(user),
          wallet_addresses: walletsForUser(user),
        }),
      })

      return response.ok
    }

    const clearSession = async () => {
      await fetch("/api/auth/privy/session", {
        method: "DELETE",
        headers: {
          accept: "application/json",
          ...(csrfToken ? { "x-csrf-token": csrfToken } : {}),
        },
        credentials: "same-origin",
      })
    }

    const completeOAuthFlow = async () => {
      const provider = window.localStorage.getItem(PROVIDER_STORAGE_KEY)
      const url = new URL(window.location.href)
      const code = url.searchParams.get("code")
      const oauthState = url.searchParams.get("state")

      if (!provider || !code || !oauthState) return

      try {
        await privy.auth.oauth.loginWithCode(code, oauthState, provider)
      } finally {
        window.localStorage.removeItem(PROVIDER_STORAGE_KEY)
        url.searchParams.delete("code")
        url.searchParams.delete("state")
        window.history.replaceState({}, "", url.toString())
      }
    }

    const refreshState = async () => {
      const result = await privy.user.get()
      const user = result?.user as PrivyUser
      state.textContent = user ? labelForUser(user) : "guest"
      button.textContent = user ? "Logout" : "Privy Login"
      return user
    }

    const toggleAuth = async () => {
      const current = await privy.user.get()
      const currentUser = current?.user as PrivyUser

      if (currentUser?.id) {
        await privy.auth.logout({ userId: currentUser.id })
        await clearSession()
        window.location.reload()
        return
      }

      const redirectURI = window.location.href
      const result = await privy.auth.oauth.generateURL("google", redirectURI)
      window.localStorage.setItem(PROVIDER_STORAGE_KEY, "google")
      window.location.assign(result.url)
    }

    button.addEventListener("click", () => void toggleAuth())

    await privy.initialize()
    await completeOAuthFlow()
    const user = await refreshState()
    if (user?.id) {
      const synced = await syncSession(user)
      if (synced && sessionState === "missing") {
        window.location.reload()
      }
    }
  },
}
