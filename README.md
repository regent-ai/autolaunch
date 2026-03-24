# Autolaunch Revenue and Emissions Contracts

This Foundry project is the Autolaunch revenue and emissions subproject inside the shared Regent contracts repo.

It owns the subject registry, splitter, ingress, and emissions contracts. It does not own the older launch, auction, fee-hook, or AgentBook stack in this pass.

## Contract set

- `src/revenue/SubjectRegistry.sol`
  Canonical subject registry keyed by `bytes32 subjectId`.
- `src/revenue/RevenueShareFactory.sol`
  Deploys one splitter per subject and provisions the subject record.
- `src/revenue/RevenueShareSplitter.sol`
  Canonical subject-side staking and revenue splitter.
- `src/revenue/RevenueIngressRouter.sol`
  Direct payment path for cooperative senders.
- `src/revenue/RevenueIngressAccount.sol`
  Sweepable deposit address for invoice-style flows.
- `src/revenue/RevenueIngressFactory.sol`
  Deterministic ingress-account deployment.
- `src/revenue/MainnetRegentEmissionsController.sol`
  Mainnet-only REGENT emissions accounting keyed by recognized mainnet USDC.
- `src/revenue/RegentEmissionsDistributorV2.sol`
  Merkle distributor kept for the current publisher rail.

## Scope

- Recognize revenue only on Ethereum, only in USDC, and only after it reaches canonical ingress or the splitter.
- Keep mainnet emissions accounting on chain.
- Treat the Merkle distributor as the test and publisher rail, not the preferred mainnet rail.
- Leave launch, auction, fee-hook, and AgentBook contracts out of this subproject.

## Build and test

```bash
cd /Users/sean/Documents/regent/contracts/autolaunch
forge build
forge test
```

## Included deployment helpers

- `scripts/DeployAutolaunchInfra.s.sol`
- `scripts/DeployPublisherFixture.s.sol`
- `scripts/DeployMainnetRegentEmissionsController.s.sol`
- `scripts/DeployRegentEmissionsDistributor.s.sol`
- `scripts/DeploySimpleMintableERC20.s.sol`

## Included tests

- `test/RevenueShareSplitter.t.sol`
- `test/RegentEmissionsDistributorV2.t.sol`
- `test/MainnetRegentEmissionsController.t.sol`
- `test/DeployMainnetRegentEmissionsControllerScript.t.sol`
- `test/DeployRegentEmissionsDistributorScript.t.sol`

## Further reading

- `docs/ARCHITECTURE_GUIDE.md`
- `docs/FOUNDRY_TESTING_GUIDE.md`
- `CONTRACTS.md`
- `REVENUE_SHARE_SPLITTER_SPEC.md`
