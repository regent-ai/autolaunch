# Foundry Dependency Pins

- `Uniswap/uerc20-factory`: `9705debfea9e6a641bc04352398f9e549055ac44`
- `Vectorized/solady`: `054a7f98588ae2ba98c2d670589743023fff539e`

UERC20 requires Solidity `0.8.28`, while local Uniswap v4 dependencies include exact
`0.8.26` sources. `foundry.toml` uses automatic compiler detection so each dependency
is compiled with the compiler version declared by its source.
