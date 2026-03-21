# Autolaunch

Standalone Phoenix LiveView app for `autolaunch.sh`, ported from Regent's legacy `/agentlaunch` surface.

## Scope

- Guided launch flow at `/launch`
- Auction market at `/auctions`
- Auction detail route at `/auctions/:id`
- Positions route at `/positions`
- Human proof flow at `/agentbook`
- Privy browser login with Phoenix session exchange
- SIWA sidecar proxy endpoints and wallet-signature verification
- CCA readiness checks, launch job persistence, bid quoting, and positions
- Public AgentBook registration and lookup flows

## Runtime env

- `DATABASE_URL` or `LOCAL_DATABASE_URL`
- `SECRET_KEY_BASE`
- `PHX_HOST`
- `PORT`
- `PRIVY_APP_ID`
- `PRIVY_VERIFICATION_KEY`
- `SIWA_INTERNAL_URL`
- `SIWA_SHARED_SECRET`
- `SIWA_HMAC_SECRET`
- `ETH_MAINNET_RPC_URL`
- `ETH_SEPOLIA_RPC_URL`
- `ETH_MAINNET_FACTORY_ADDRESS` or `ETH_FACTORY_ADDRESS`
- `ETH_MAINNET_UNISWAP_V4_POOL_MANAGER` or `ETH_UNISWAP_V4_POOL_MANAGER`
- `ETH_MAINNET_USDC_ADDRESS`
- `ETH_SEPOLIA_USDC_ADDRESS`
- `REGENT_EMISSIONS_DISTRIBUTOR_ADDRESS`
- `AUTOLAUNCH_DEPLOY_WORKDIR`
- `AUTOLAUNCH_DEPLOY_BINARY`
- `AUTOLAUNCH_DEPLOY_SCRIPT_TARGET`
- `AUTOLAUNCH_DEPLOY_ACCOUNT` or `AUTOLAUNCH_DEPLOY_PRIVATE_KEY`
- `AUTOLAUNCH_CHAIN_ID`
- `AUTOLAUNCH_EPOCH_GENESIS_TS`
- `AUTOLAUNCH_EPOCH_SECONDS`
- `AUTOLAUNCH_PUBLISHER_ENABLED`
- `AUTOLAUNCH_PUBLISHER_INTERVAL_MS`
- `WORLD_ID_APP_ID`
- `WORLD_ID_ACTION`
- `WORLD_ID_RP_ID`
- `WORLD_ID_SIGNING_KEY`
- `WORLDCHAIN_RPC_URL`
- `WORLDCHAIN_AGENTBOOK_ADDRESS`
- `WORLDCHAIN_AGENTBOOK_RELAY_URL`
- `BASE_MAINNET_RPC_URL`
- `BASE_AGENTBOOK_ADDRESS`
- `BASE_AGENTBOOK_RELAY_URL`
- `BASE_SEPOLIA_RPC_URL`
- `BASE_SEPOLIA_AGENTBOOK_ADDRESS`
- `BASE_SEPOLIA_AGENTBOOK_RELAY_URL`

## Routes

- `/`
- `/launch`
- `/auctions`
- `/auctions/:id`
- `/positions`
- `/agentbook`
- `/health`
- `/api/auth/privy/session`
- `/api/agents`
- `/api/agents/:id`
- `/api/agents/:id/readiness`
- `/api/launch/preview`
- `/api/launch/jobs`
- `/api/launch/jobs/:id`
- `/api/auctions`
- `/api/auctions/:id`
- `/api/auctions/:id/bid_quote`
- `/api/auctions/:id/bids`
- `/api/me/bids`
- `/api/bids/:id/exit`
- `/api/bids/:id/claim`
- `/api/agentbook/sessions`
- `/api/agentbook/sessions/:id`
- `/api/agentbook/sessions/:id/submit`
- `/api/agentbook/lookup`
- `/api/agentbook/verify`
- `/v1/agent/siwa/nonce`
- `/v1/agent/siwa/verify`

## Notes

- This app uses LiveView as the source of truth for page state.
- TypeScript is limited to Privy browser auth, wallet signing, and motion hooks.
- The canonical CLI lives in [`regent-cli`](/Users/sean/Documents/regent/techtree/regent-cli) as `regent autolaunch ...`.
- Public launches are Ethereum-only. The user does not choose a chain in the launch form. `AUTOLAUNCH_CHAIN_ID` decides whether the environment is mainnet (`1`) or Sepolia (`11155111`).
- The launch worker expects the hard-cut `CCA_RESULT_JSON` payload with registry, rights hub, vault, and Base emissions addresses. It no longer reads the old fee-vault and pool-id payload.
- Launch jobs now collect a recovery Safe, auction proceeds recipient, Ethereum revenue treasury, Base revenue treasury, Tempo revenue treasury, and Base emission recipient.
- Revenue and emissions use fixed 72-hour epochs (`259200` seconds) from `AUTOLAUNCH_EPOCH_GENESIS_TS`.
- The publisher worker is a separate background path. It stores epoch roots, revenue snapshots, and REGENT epoch records in app tables and is enabled with `AUTOLAUNCH_PUBLISHER_ENABLED=true`.
- Tempo is present in the data model as a reserved routing seam only. It is not active in the v0.1 publisher flow.
- The launch contracts are not defined in this repo. The canonical Solidity sources for the CCA deploy flow, hook ingress, revenue rights hub, revenue vaults, registry, and Base emissions distributor live in [`monorepo/contracts`](/Users/sean/Documents/regent/monorepo/contracts).
- The launch worker is real-deploy by default; mock deploy is opt-in with `AUTOLAUNCH_MOCK_DEPLOY=true`.
