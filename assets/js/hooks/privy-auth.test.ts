import assert from "node:assert/strict"
import { describe, it } from "node:test"

import { switchWalletSession } from "./privy-auth.ts"
import type { EthereumProvider, PrivyUser } from "./privy-wallet.ts"

function providerFor(account: string): EthereumProvider {
  return {
    async request(args: { method: string }) {
      if (args.method === "eth_requestAccounts") return [account]
      if (args.method === "eth_chainId") return "0xaa36a7"
      throw new Error(`Unexpected provider method: ${args.method}`)
    },
  }
}

describe("switchWalletSession", () => {
  it("keeps the current session when the requested wallet is not active", async () => {
    let loggedOut = false
    let clearedSession = false
    let loginCalled = false

    await assert.rejects(
      () =>
        switchWalletSession({
          targetWallet: "0x2222222222222222222222222222222222222222",
          getCurrentUser: async () => ({ id: "user_123" } satisfies PrivyUser),
          requireProvider: async () => providerFor("0x1111111111111111111111111111111111111111"),
          logout: async () => {
            loggedOut = true
          },
          clearSession: async () => {
            clearedSession = true
          },
          loginAndSync: async () => {
            loginCalled = true
            return { id: "user_456" }
          },
        }),
      /Switch to wallet 0x2222222222222222222222222222222222222222 before continuing\./,
    )

    assert.equal(loggedOut, false)
    assert.equal(clearedSession, false)
    assert.equal(loginCalled, false)
  })

  it("switches sessions after the requested wallet is already active", async () => {
    const calls: string[] = []

    const user = await switchWalletSession({
      targetWallet: "0x2222222222222222222222222222222222222222",
      getCurrentUser: async () => ({ id: "user_123" } satisfies PrivyUser),
      requireProvider: async () => providerFor("0x2222222222222222222222222222222222222222"),
      logout: async (userId) => {
        calls.push(`logout:${userId}`)
      },
      clearSession: async () => {
        calls.push("clear")
      },
      loginAndSync: async (expectedWallet) => {
        calls.push(`login:${expectedWallet}`)
        return { id: "user_456" }
      },
    })

    assert.deepEqual(calls, [
      "logout:user_123",
      "clear",
      "login:0x2222222222222222222222222222222222222222",
    ])
    assert.deepEqual(user, { id: "user_456" })
  })
})
