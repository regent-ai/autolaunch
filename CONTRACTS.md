# Autolaunch Contracts Overview

This subproject tells the Autolaunch revenue and emissions story:

1. Create the canonical subject record in `SubjectRegistry`.
2. Create the subject's `RevenueShareSplitter` and default ingress account.
3. Route recognized Ethereum USDC into `RevenueShareSplitter`.
4. Publish mainnet emissions through `MainnetRegentEmissionsController` once subject revenue has been credited on chain.

## Current rules

- Only recognize revenue on Ethereum, in USDC, after it reaches the canonical ingress and is swept into the splitter.
- On mainnet, prefer the onchain emissions controller over the Merkle distributor.
- Keep the revenue path hard-cut. Do not reintroduce the old rights-hub or vault story.

## Deployment helpers in this subproject

- `DeployAutolaunchInfra.s.sol` deploys the subject registry, splitter factory, ingress router, and ingress factory.
- `DeployMainnetRegentEmissionsController.s.sol` deploys the mainnet emissions controller.
- `DeployRegentEmissionsDistributor.s.sol` deploys the Merkle distributor rail.
- `DeployPublisherFixture.s.sol` builds a local fixture for publisher and integration tests.
- `DeploySimpleMintableERC20.s.sol` deploys a simple token for local or test use.

## What this subproject does not contain

- Launch auction deployment
- Fee-hook deployment
- Launch pool registry and vault
- AgentBook or World ID contracts

Those surfaces remain out of scope for this hard cut.
