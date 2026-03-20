import type { Hook } from "phoenix_live_view"

interface EthereumProvider {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>
}

interface TransactionReceipt {
  status?: string
}

interface WalletTxHookInstance {
  el: HTMLElement
  pushEvent(event: string, payload: Record<string, unknown>): void
  handleClick?: EventListener
}

declare global {
  interface Window {
    ethereum?: EthereumProvider
  }
}

const POLL_INTERVAL_MS = 2_000
const MAX_POLLS = 45

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content?.trim() || ""
}

function parseJsonAttr(value: string | undefined): Record<string, unknown> {
  if (!value) return {}

  try {
    const parsed = JSON.parse(value) as Record<string, unknown>
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

function hexChainId(chainId: number): string {
  return `0x${chainId.toString(16)}`
}

async function ensureWalletChain(ethereum: EthereumProvider, chainId: number): Promise<void> {
  const current = (await ethereum.request({ method: "eth_chainId" })) as string
  if (parseInt(current, 16) === chainId) return

  await ethereum.request({
    method: "wallet_switchEthereumChain",
    params: [{ chainId: hexChainId(chainId) }],
  })
}

async function registerConfirmedTx(
  endpoint: string,
  baseBody: Record<string, unknown>,
  txHash: string,
): Promise<void> {
  const headers: Record<string, string> = {
    accept: "application/json",
    "content-type": "application/json",
  }

  const token = csrfToken()
  if (token) headers["x-csrf-token"] = token

  for (let attempt = 0; attempt < MAX_POLLS; attempt += 1) {
    const response = await fetch(endpoint, {
      method: "POST",
      headers,
      credentials: "same-origin",
      body: JSON.stringify({ ...baseBody, tx_hash: txHash }),
    })

    const payload = (await response.json().catch(() => ({}))) as {
      ok?: boolean
      error?: { code?: string; message?: string }
    }

    if (response.status === 202 || payload.error?.code === "transaction_pending") {
      await new Promise((resolve) => window.setTimeout(resolve, POLL_INTERVAL_MS))
      continue
    }

    if (!response.ok || payload.ok === false) {
      throw new Error(payload.error?.message || "Failed to register transaction.")
    }

    return
  }

  throw new Error("Timed out waiting for chain confirmation.")
}

async function waitForReceipt(ethereum: EthereumProvider, txHash: string): Promise<void> {
  for (let attempt = 0; attempt < MAX_POLLS; attempt += 1) {
    const receipt = (await ethereum.request({
      method: "eth_getTransactionReceipt",
      params: [txHash],
    })) as TransactionReceipt | null

    if (!receipt) {
      await new Promise((resolve) => window.setTimeout(resolve, POLL_INTERVAL_MS))
      continue
    }

    if (receipt.status === "0x1") return
    if (receipt.status === "0x0") throw new Error("Transaction reverted onchain.")

    await new Promise((resolve) => window.setTimeout(resolve, POLL_INTERVAL_MS))
  }

  throw new Error("Timed out waiting for chain confirmation.")
}

export const WalletTxButton: Hook = {
  mounted() {
    const hook = this as unknown as WalletTxHookInstance
    const onClick = async () => {
      const button = hook.el as HTMLButtonElement
      if (button.disabled) return

      const ethereum = window.ethereum
      if (!ethereum) {
        hook.pushEvent("wallet_tx_error", { message: "Connect an EVM wallet in this browser first." })
        return
      }

      const chainId = Number(button.dataset.chainId || "")
      const to = button.dataset.to || ""
      const data = button.dataset.data || ""
      const value = button.dataset.value || "0x0"
      const registerEndpoint = button.dataset.registerEndpoint || ""
      const registerBody = parseJsonAttr(button.dataset.registerBody)
      const pendingMessage = button.dataset.pendingMessage || "Transaction sent. Waiting for confirmation."
      const successMessage = button.dataset.successMessage || "Transaction confirmed."

      if (!Number.isInteger(chainId) || !to || !data) {
        hook.pushEvent("wallet_tx_error", { message: "Wallet action is missing required transaction data." })
        return
      }

      button.disabled = true
      hook.pushEvent("wallet_tx_started", { message: pendingMessage })

      try {
        const accountResult = await ethereum.request({ method: "eth_requestAccounts" })
        const from = Array.isArray(accountResult) ? String(accountResult[0] || "") : ""
        if (!from) throw new Error("Wallet connection was cancelled.")

        await ensureWalletChain(ethereum, chainId)

        const txHash = (await ethereum.request({
          method: "eth_sendTransaction",
          params: [{ from, to, data, value }],
        })) as string

        if (registerEndpoint) {
          await registerConfirmedTx(registerEndpoint, registerBody, txHash)
        } else {
          await waitForReceipt(ethereum, txHash)
        }

        hook.pushEvent("wallet_tx_registered", { message: successMessage, tx_hash: txHash })
      } catch (error) {
        const message = error instanceof Error ? error.message : "Wallet transaction failed."
        hook.pushEvent("wallet_tx_error", { message })
      } finally {
        button.disabled = false
      }
    }

    hook.handleClick = onClick
    hook.el.addEventListener("click", onClick)
  },

  destroyed() {
    const hook = this as unknown as WalletTxHookInstance
    if (hook.handleClick) {
      hook.el.removeEventListener("click", hook.handleClick)
    }
  },
}
