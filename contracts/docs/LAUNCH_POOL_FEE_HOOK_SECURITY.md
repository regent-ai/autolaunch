# Launch Pool Fee Hook Security Note

`LaunchPoolFeeHook` is high-risk launch infrastructure because it uses Uniswap v4
return deltas. Its enabled permissions are:

- `beforeSwap`
- `afterSwap`
- `beforeSwapReturnDelta`
- `afterSwapReturnDelta`

The hook must only charge fees in the quote token configured for the launch pool. Tests
must prove that only the PoolManager can call swap callbacks, quote-token fees are the
only fees taken, returned deltas match the amount accrued into the vault, and vault
balances equal the treasury plus Regent split.

The hook callbacks must stay constant-size. Do not add user-controlled arrays or
unbounded loops to callback paths.
