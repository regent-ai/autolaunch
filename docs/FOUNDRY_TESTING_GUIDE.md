# Foundry Testing Guide for the Autolaunch Cutover Contracts

This guide explains how to test the hard-cutover contract set in Foundry.

It covers:

- what each existing test is proving,
- what integration tests should be added next,
- which invariants matter most,
- and how the CCA launch lane should be mocked when testing end-to-end behavior.

---

## 1. Test philosophy

The rewrite has two very different kinds of contract behavior:

1. **deterministic accounting contracts**
   - `RevenueShareSplitter`
   - `MainnetRegentEmissionsController`
   - `SubjectRegistry`
2. **routing / wiring contracts**
   - `RevenueShareFactory`
   - `RevenueIngressRouter`
   - `RevenueIngressAccount`
   - `RevenueIngressFactory`

The most important tests are not “did the function run?” but:

- does value conserve,
- does claim math stay correct across mixed stake/revenue timing,
- are duplicate claims impossible,
- do unsupported reward tokens fail cleanly,
- does the system behave correctly when supply changes,
- does USDC-only emissions accounting remain legible.

---

## 2. Existing tests in this package

### `test/RevenueShareSplitter.t.sol`

This file already covers the core economics.

#### `testMainScenarioAccounting`
Checks the full mixed-flow scenario:

- initial staking,
- USDC ingress sweep,
- additional stake,
- partial unstake,
- WETH ingress sweep,
- selective claim,
- full unstake,
- second USDC sweep,
- batch claim.

This is the main “does the business logic make sense” test.

#### `testTreasuryStakingIsRevenueNeutral`
Proves that treasury staking its own inventory does not create new revenue out of thin air.
It only changes *where* treasury value sits:

- treasury residual, or
- treasury-as-staker claim.

#### `testBurnChangesFutureDepositsOnly`
Checks that a supply burn affects **future** deposits only, not already accrued rewards.

#### `testUnsupportedRewardTokenDoesNotSweep`
Checks that unallowlisted junk tokens cannot pollute splitter accounting.

#### `testStakeTokenCanAlsoBeRewardToken`
Checks that the stake token itself can also be an allowed reward token without corrupting principal accounting.

#### `testSecondSweepOfSameBalanceCreditsZero`
Checks the balance-delta / full-balance sweep assumption: a second sweep of already-swept funds should not create new accounting credit.

### `test/RegentEmissionsDistributorV2.t.sol`

This file covers the safer Merkle distributor variant.

#### `testPublishAndClaimEmission`
Checks normal publish + claim flow.

#### `testRejectsDuplicateClaimByIndex`
Checks replay protection for the same `(epoch, index)`.

#### `testRejectsDuplicateSubjectAcrossIndexes`
Checks duplicate-subject protection when the same subject appears at multiple indexes.

---

## 3. Recommended Foundry commands

Typical local runs:

```bash
forge test -vv
forge test --match-contract RevenueShareSplitterTest -vvv
forge test --match-contract RegentEmissionsDistributorV2Test -vvv
forge test --match-test testMainScenarioAccounting -vvvv
```

Gas snapshots once compile is wired:

```bash
forge test --gas-report
```

Fuzzing targeted tests:

```bash
forge test --match-test testFuzz_ -vv
```

---

## 4. The core splitter invariants

These are the invariants worth encoding in invariant tests.

### Invariant A: post-skim value is conserved
For every reward token `R`:

```text
recognizedNet(R)
= protocolReserve(R)
+ treasuryResidual(R)
+ totalClaimedToUsers(R)
+ currentUnclaimedUserEntitlement(R)
+ undistributedDust(R)
```

Depending on test harness shape, `totalClaimedToUsers + currentUnclaimedUserEntitlement` can be represented by tracking deposits and user balances.

### Invariant B: users only earn on stake / totalSupply
For any single deposit `A` after protocol skim:

```text
userDelta = net * userStake / totalSupplyAtDeposit
```

not `userStake / totalStaked`.

### Invariant C: unstaked supply stays with treasury
For any recognized deposit:

```text
treasuryPortion = net - floor(net * totalStaked / totalSupply)
```

### Invariant D: no double claim
A claim can only transfer what is currently stored/pending for that user and token.
After claim, the same entitlement cannot be transferred again.

### Invariant E: no double sweep credit
If an ingress account holds zero balance, another sweep of the same token must not create any new accounting effect.

### Invariant F: old deposits do not change when supply changes later
Burns or mints after a deposit affect only later deposits.

---

## 5. Scenario table for the main splitter test

Use this table as the reference scenario when debugging the accounting rewrite.

Assumptions:

- `XYZ` total supply = `1_000e18`
- `USDC` has `6` decimals
- `WETH` has `18` decimals
- protocol skim = `100 bps`
- initial stakes:
  - Alice `200e18`
  - Bob `100e18`
  - Carol `50e18`
  - Dave `30e18`
  - Eve `20e18`

Initial total staked = `400e18`.

| Step | Action | Assertions |
|---|---|---|
| 0 | initial stake setup | `totalStaked = 400e18` |
| 1 | sweep `10_000e6 USDC` | protocol reserve `100e6`, treasury residual `5_940e6`, Alice `1_980e6`, Bob `990e6`, Carol `495e6`, Dave `297e6`, Eve `198e6` |
| 2 | Bob stakes `+50e18` | Bob keeps prior USDC entitlement; `totalStaked = 450e18` |
| 3 | Dave unstakes `10e18` | Dave keeps prior USDC entitlement; `totalStaked = 440e18` |
| 4 | sweep `1_000e18 WETH` | protocol reserve `10e18`, treasury residual `554.4e18`, Alice `198e18`, Bob `148.5e18`, Carol `49.5e18`, Dave `19.8e18`, Eve `19.8e18` |
| 5 | Alice claims only USDC | Alice USDC pending becomes `0`, Alice WETH remains pending |
| 6 | Carol fully unstakes | Carol keeps old USDC/WETH entitlement, `totalStaked = 390e18` |
| 7 | sweep `5_000e6 USDC` | protocol reserve total `150e6`, treasury residual total `8_959.5e6`, Carol gets no new USDC |
| 8 | Bob batch claims | Bob receives `1_732.5e6 USDC` and `148.5e18 WETH` |

---

## 6. New tests that should be added next

### A. `MainnetRegentEmissionsController.t.sol`

This is the most important missing test file.

Add coverage for:

#### `testCreditUsdcDirect`
- create subject
- grant `CREDIT_ROLE`
- call `creditUsdc(...)`
- assert `subjectRevenueUsdc[currentEpoch][subjectId]`
- assert epoch total increased

#### `testPullSplitterUsdc`
- deposit USDC into splitter
- ensure splitter protocol reserve grows
- call `pullSplitterUsdc(...)`
- assert emissions controller credited correct amount

#### `testPullLaunchVaultUsdc`
- mock a USDC-only launch route
- pull from mocked launch vault
- assert epoch credit

#### `testRecipientSnapshotFreezesAtFirstCredit`
- set emission recipient A
- credit subject in epoch N
- change registry recipient to B
- assert snapshot remains A for epoch N

#### `testPublishEpochEmission`
- advance time past epoch close
- fund REGENT
- publish epoch
- assert emission amount stored and REGENT funded

#### `testClaimSingleSubject`
- set subject revenue = 25
- total epoch revenue = 100
- emission amount = 40 REGENT
- expected claim = 10 REGENT

#### `testClaimMany`
- two or more epochs for same subject
- assert batch claim equals sum

#### `testDuplicateClaimBlocked`
- claim once
- second claim reverts

#### `testCreditIdReplayBlocked`
- same `creditId` twice should revert

#### `testCannotPublishCurrentEpoch`
- `publishEpochEmission(epoch >= currentEpoch())` should revert

### B. `RevenueIngressRouter.t.sol`

Add:

- `depositToken` routes to correct subject splitter
- `depositNative` routes to correct subject splitter
- paused router blocks deposits
- unknown subject reverts

### C. `RevenueIngressFactory.t.sol`

Add:

- deterministic ingress deployment
- expected owner assignment
- ingress indexed under splitter

### D. `RevenueShareFactory.t.sol`

Add:

- splitter deployed once per stake token
- subject registered correctly
- emission recipient optionally configured
- reward-token allowlist seeded as expected

### E. `SubjectRegistry.t.sol`

Add:

- subject creation and updates
- treasury safe as default manager
- identity link / unlink behavior
- one identity cannot be linked to two subjects
- emission recipient per chain

---

## 7. Suggested integration harness for launch-side testing

The cutover package does not itself include the full CCA / launch hook system, so integration tests should use mocks for launch-side interfaces.

### Minimal mocks to add

- `MockLaunchFeeVault.sol`
  - stores treasury and Regent balances per pool / token
  - supports `withdrawTreasury(...)`
  - supports `withdrawRegentShare(...)`
- `MockLaunchFeeRegistry.sol`
  - stores pool recipient config
- `MockLaunchPoolFeeHook.sol`
  - can simulate fee accrual into the mock vault

### Main end-to-end launch integration test

Suggested flow:

1. deploy `SubjectRegistry`
2. deploy `RevenueShareFactory`
3. create splitter for subject
4. deploy ingress account(s)
5. deploy mock launch vault and seed fees
6. pull treasury share from launch vault into splitter
7. pull USDC Regent share from launch vault into emissions controller
8. stake users
9. claim splitter rewards
10. publish emissions epoch
11. claim REGENT

Assertions:

- staker rewards reflect launch-vault pulls,
- treasury residual reflects unstaked share,
- emissions credit is USDC-only,
- subject claim amount matches credited share.

---

## 8. Fuzz tests worth adding

### Splitter fuzzing

#### `testFuzz_DepositMatchesStakeSupplyRule`
Randomize:

- total supply,
- staked amounts,
- deposit size,
- protocol skim bps.

Assert:

```text
previewDelta(user) == floor(net * userStake / supply)
```

#### `testFuzz_UnstakePreservesPastEntitlement`
Randomize:

- a deposit before unstake,
- unstake amount,
- a deposit after unstake.

Assert:

- user keeps pre-unstake earnings,
- post-unstake earnings use new balance only.

#### `testFuzz_ClaimDoesNotOverpay`
Randomize several deposits and claims.

Assert:

- claimed <= cumulative entitlement,
- post-claim immediate second claim is zero.

### Emissions fuzzing

#### `testFuzz_ClaimAmountIsProRata`
Randomize:

- subject revenue,
- total revenue,
- emission amount.

Assert:

```text
claim == floor(emissionAmount * subjectRevenue / totalRevenue)
```

---

## 9. Invariant test ideas

If you build `StdInvariant` harnesses, prioritize these two.

### `SplitterInvariant`
Random actions:

- stake,
- unstake,
- depositToken,
- claim,
- claimAllKnown,
- burn supply.

Check:

- value conservation,
- no negative balances,
- no reward token credited unless allowlisted,
- treasury/protocol withdrawals bounded by reserves.

### `EmissionsInvariant`
Random actions:

- creditUsdc,
- pullSplitterUsdc,
- publish epoch,
- claim.

Check:

- no double subject claim per epoch,
- no claim without published epoch,
- credited revenue accumulates monotonically inside an open epoch.

---

## 10. Recommended folder additions

Add these test files next:

```text
test/
  RevenueShareSplitter.t.sol
  RevenueShareFactory.t.sol
  RevenueIngressRouter.t.sol
  RevenueIngressFactory.t.sol
  SubjectRegistry.t.sol
  MainnetRegentEmissionsController.t.sol
  integration/
    LaunchToSplitterIntegration.t.sol
    LaunchToEmissionsIntegration.t.sol
  mocks/
    MintableBurnableERC20Mock.sol
    MockLaunchFeeVault.sol
    MockLaunchFeeRegistry.sol
    MockLaunchPoolFeeHook.sol
```

---

## 11. Most important assertion to keep in mind

For the splitter, the entire rewrite hangs on one rule:

```text
a staker earns stake / totalSupply of post-skim inflow
```

So the accumulator line must be equivalent to:

```text
accRewardPerToken += netAfterProtocol / totalSupply
```

not:

```text
accRewardPerToken += stakerPortion / totalSupply
```

That single line is the difference between correct accounting and systematic underpayment.
