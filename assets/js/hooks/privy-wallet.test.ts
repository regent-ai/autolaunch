import assert from "node:assert/strict"
import { describe, it } from "node:test"

import {
  labelForUser,
  parseChainId,
  walletForUser,
  walletsForUser,
} from "./privy-wallet.ts"

describe("privy wallet helpers", () => {
  it("pulls the canonical wallet from the Privy user", () => {
    assert.equal(
      walletForUser({
        wallet: { address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },
        linked_accounts: [{ address: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" }],
      }),
      "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    )
  })

  it("collects deduplicated wallet addresses", () => {
    assert.deepEqual(
      walletsForUser({
        wallet: { address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },
        linked_accounts: [
          { address: "0xBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" },
          { address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },
        ],
      }),
      [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      ],
    )
  })

  it("prefers email labels and falls back to short wallet addresses", () => {
    assert.equal(
      labelForUser({
        email: { address: "operator@autolaunch.sh" },
        wallet: { address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },
      }),
      "operator@autolaunch.sh",
    )

    assert.equal(
      labelForUser({
        wallet: { address: "0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" },
      }),
      "0xaaaa...aaaa",
    )
  })

  it("parses hex and eip155 chain ids", () => {
    assert.equal(parseChainId("0x14a34"), 84532)
    assert.equal(parseChainId("eip155:8453"), 8453)
    assert.equal(parseChainId(1), 1)
    assert.equal(parseChainId("bad"), null)
  })
})
