| Contract (module)                      | What it gives                                                                      |          **Testnet** |          **Mainnet** |
| -------------------------------------- | ---------------------------------------------------------------------------------- | -------------------: | -------------------: |
| **DeFiActions**                        | Core interfaces: `Source`, `Sink`, `Swapper`, `PriceOracle`, `Flasher` (+ helpers) | `0x4c2ff9dd03ab442f` | `0x92195d814edf9cb0` |
| **DeFiActionsMathUtils**               | Math helpers used by Actions                                                       | `0x4c2ff9dd03ab442f` | `0x92195d814edf9cb0` |
| **DeFiActionsUtils**                   | Misc utils and shared types (`Quote`, `UniqueIdentifier`, etc.)                    | `0x4c2ff9dd03ab442f` | `0x92195d814edf9cb0` |
| **FungibleTokenConnectors**            | Basic FT **Source/Sink** (vault in/out)                                            | `0x5a7b9cee9aaf4e4e` | `0x1d9a619393e9fb53` |
| **SwapConnectors**                     | Generic **Swap** composition (`SwapSource`, adapters)                              | `0xaddd594cf410166a` | `0x0bce04a00aedf132` |
| **IncrementFiSwapConnectors**          | IncrementFi **Swapper** / zap paths                                                | `0x49bae091e5ea16b5` | `0xefa9bd7d1b17f1ed` |
| **IncrementFiFlashloanConnectors**     | IncrementFi **Flasher**                                                            | `0x49bae091e5ea16b5` | `0xefa9bd7d1b17f1ed` |
| **IncrementFiPoolLiquidityConnectors** | IncrementFi pool/zapper utilities                                                  | `0x49bae091e5ea16b5` | `0xefa9bd7d1b17f1ed` |
| **IncrementFiStakingConnectors**       | IncrementFi staking **Source/Sink** (rewards, restake)                             | `0x49bae091e5ea16b5` | `0xefa9bd7d1b17f1ed` |
| **BandOracleConnectors**               | **PriceOracle** via Band                                                           | `0x1a9f5d18d096cd7a` | `0xf627b5c89141ed99` |
| **EVMNativeFLOWConnectors**            | FLOW (EVM) **Source/Sink**                                                         | `0xb88ba0e976146cd1` | `0xcc15a0c9c656b648` |
| **EVMTokenConnectors**                 | EVM ERC-20-style **Source/Sink**                                                   | `0xb88ba0e976146cd1` | `0xcc15a0c9c656b648` |
| **UniswapV2Connectors**                | Uniswap-V2 style **Swapper** (Flow EVM)                                            | `0xfef8e4c5c16ccda5` | `0x0e5b1dececaca3a8` |
