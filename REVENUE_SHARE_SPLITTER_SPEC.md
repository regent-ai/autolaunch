# Current Subject Revenue Path

This note describes the revenue path owned by `contracts/autolaunch`.

## Revenue path

- `SubjectRegistry` stores the canonical subject record, identity links, and emission recipient.
- `RevenueShareFactory` provisions the subject-side splitter.
- `RevenueShareSplitter` is the current treasury recipient for recognized Ethereum USDC revenue.
- `RevenueIngressAccount.sweepUSDC()` is the canonical recognition point for invoice-style agent revenue.
- `RevenueIngressRouter` is the cooperative sender path for direct USDC deposits.
- `MainnetRegentEmissionsController` is the preferred mainnet emissions contract once revenue is being credited on chain.
- `RegentEmissionsDistributorV2` remains the current Sepolia and publisher distribution path.

## What is not part of this subproject

- No rights-hub or Merkle revenue vault path.
- No launch, auction, fee-hook, or AgentBook contracts.
- No Base-specific emissions story.
