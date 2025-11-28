# UniswapX

[![Integration Tests](https://github.com/Uniswap/uniswapx/actions/workflows/test-integration.yml/badge.svg)](https://github.com/Uniswap/uniswapx/actions/workflows/test-integration.yml)
[![Unit Tests](https://github.com/Uniswap/uniswapx/actions/workflows/test.yml/badge.svg)](https://github.com/Uniswap/uniswapx/actions/workflows/test.yml)

UniswapX is an ERC20 swap settlement protocol that provides swappers with a gasless experience, MEV protection, and access to arbitrary liquidity sources. Swappers generate signed orders which specify the specification of their swap, and fillers compete using arbitrary fill strategies to satisfy these orders.


## UniswapX Protocol Architecture

![Architecture](./assets/uniswapx-architecture.png)

### Reactors

Order Reactors _settle_ UniswapX orders. They are responsible for validating orders of a specific type, resolving them into inputs and outputs, and executing them against the filler's strategy, and verifying that the order was successfully fulfilled.

Reactors process orders using the following steps:
- Validate the order
- Resolve the order into inputs and outputs
- Pull input tokens from the swapper to the fillContract using permit2 `permitWitnessTransferFrom` with the order as witness
- Call `reactorCallback` on the fillContract
- Transfer output tokens from the fillContract to the output recipients

Reactors implement the [IReactor](./src/interfaces/IReactor.sol) interface which abstracts the specifics of the order specification. This allows for different reactor implementations with different order formats to be used with the same interface, allowing for shared infrastructure and easy extension by fillers.

Current reactor implementations:
- [LimitOrderReactor](./src/reactors/LimitOrderReactor.sol): A reactor that settles simple static limit orders
- [DutchOrderReactor](./src/reactors/DutchOrderReactor.sol): A reactor that settles linear-decay dutch orders
- [ExclusiveDutchOrderReactor](./src/reactors/ExclusiveDutchOrderReactor.sol): A reactor that settles linear-decay dutch orders with a period of exclusivity before decay begins

### Fill Contracts

Order fillContracts _fill_ UniswapX orders. They specify the filler's strategy for fulfilling orders and are called by the reactor with `reactorCallback` when using `executeWithCallback` or `executeBatchWithCallback`.

Some sample fillContract implementations are provided in this repository:
- [SwapRouter02Executor](./src/sample-executors/SwapRouter02Executor.sol): A fillContract that uses UniswapV2 and UniswapV3 via the SwapRouter02 router

### Direct Fill

If a filler wants to simply fill orders using funds held by an address rather than using a fillContract strategy, they can do so gas efficiently by using `execute` or `executeBatch`. These functions cause the reactor to skip the `reactorCallback` and simply pull tokens from the filler using `msg.sender`.

# Integrating with UniswapX
Jump to the docs for [Creating a Filler Integration](https://docs.uniswap.org/contracts/uniswapx/guides/createfiller).

# Deployment Addresses

## Ethereum Mainnet

| Contract                      | Address                                                                                                               | Source                                                                                                                    |
| ---                           | ---                                                                                                                   | ---                                                                                                                       |
| V2 Dutch Order Reactor        | [0x00000011F84B9aa48e5f8aA8B9897600006289Be](https://etherscan.io/address/0x00000011F84B9aa48e5f8aA8B9897600006289Be) | [V2DutchOrderReactor](https://github.com/Uniswap/UniswapX/blob/v2.0.0/src/reactors/V2DutchOrderReactor.sol)               |
| Exclusive Dutch Order Reactor | [0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4](https://etherscan.io/address/0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4) | [ExclusiveDutchOrderReactor](https://github.com/Uniswap/UniswapX/blob/v1.1.0/src/reactors/ExclusiveDutchOrderReactor.sol) |
| OrderQuoter                   | [0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF](https://etherscan.io/address/0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF) | [OrderQuoter](https://github.com/Uniswap/UniswapX/blob/v1.1.0/src/lens/OrderQuoter.sol)                                   |
| Permit2                       | [0x000000000022D473030F116dDEE9F6B43aC78BA3](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3) | [Permit2](https://github.com/Uniswap/permit2)                                                                             |

## Base

| Contract                      | Address                                                                                                               | Source                                                                                                                    |
| ---                           | ---                                                                                                                   | ---                                                                                                                       |
| Priority Order Reactor        | [0x000000001Ec5656dcdB24D90DFa42742738De729](https://basescan.org/address/0x000000001Ec5656dcdB24D90DFa42742738De729) | [PriorityOrderReactor](https://github.com/Uniswap/UniswapX/blob/v2.1.0/src/reactors/PriorityOrderReactor.sol)             |
| OrderQuoter                   | [0x88440407634f89873c5d9439987ac4be9725fea8](https://basescan.io/address/0x88440407634f89873c5d9439987ac4be9725fea8)  | [OrderQuoter](https://github.com/Uniswap/UniswapX/blob/v2.1.0/src/lens/OrderQuoter.sol)                                   |
| Permit2                       | [0x000000000022D473030F116dDEE9F6B43aC78BA3](https://basescan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3)  | [Permit2](https://github.com/Uniswap/permit2)                                                                             |

# Usage

```
# install dependencies
forge install

# compile contracts
forge build

# run unit tests
forge test

# run integration tests
FOUNDRY_PROFILE=integration forge test
```

# Fee-on-Transfer Disclaimer

Note that UniswapX handles fee-on-transfer tokens by transferring the amount specified to the recipient. This means that the actual amount received by the recipient will be _after_ fees.

# Version Log

| Version Number    | Commit | Contract Address |
| -------- | ------- | ------|
| 1.0 | [597cf617dd6d32b3f181edbc37aed11bc5648d93](https://github.com/Uniswap/UniswapX/commit/597cf617dd6d32b3f181edbc37aed11bc5648d93) | Contract no longer in use. Read more about the bug [here](https://github.com/Uniswap/UniswapX/commit/cf53fc7dd48029a9189d26812d676a4ea9d08d6c).
| 1.1 | [cf53fc7dd48029a9189d26812d676a4ea9d08d6c](https://github.com/Uniswap/UniswapX/commit/cf53fc7dd48029a9189d26812d676a4ea9d08d6c) | [0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4](https://etherscan.io/address/0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4) |
| 2.0 | [4bacf632512ec5c9504a78ad1b7e1aec7efc6767](https://github.com/Uniswap/UniswapX/commit/4bacf632512ec5c9504a78ad1b7e1aec7efc6767) | [0x00000011f84b9aa48e5f8aa8b9897600006289be](https://etherscan.io/address/0x00000011f84b9aa48e5f8aa8b9897600006289be) |

# Audit

### V1
- [ABDK](./audit/v1/ABDK.pdf)

### V1.1
- [ABDK](./audit/v1.1/ABDK.pdf)
- [OpenZeppelin](./audit/v1.1/OpenZeppelin.pdf)

### V2
- [Spearbit](./audit/v2/spearbit.pdf)

## Bug Bounty

This repository is subject to the Uniswap Labs Bug Bounty program, per the terms defined [here](https://uniswap.org/bug-bounty).

## Deployment:


Hyperliquid:

forge script script/DeployFeeControllerInputFees.s.sol:DeployFeeControllerInputFees  --fork-url hypercore --broadcast --legacy
    Fee controller 0x14702D5191594228e9d65C6B498be3376d323Ad2

forge script script/DeployDutch.s.sol:DeployDutch  --fork-url hypercore --broadcast --legacy

  Dutch Reactor 0xB6B65A1C7F1AFf294AA7059e87F9E498e2b51f70
  Quoter 0xf84e4C5Da759BF2B0F0E05C527b5cd0a5a6d2d5B

forge script script/DeployDutchV2.s.sol:DeployDutchV2  --fork-url hypercore --broadcast --legacy

  Owner 0x1681910dEDc43B7F7FEfBA9FbDB7357Bfd4694c8
  Reactor 0xb0c27699f420ac4e1FA630D11B9341f302C45E7a


forge script script/DeploySwapRouter02Executor.s.sol:DeploySwapRouter02Executor  --fork-url hypercore --broadcast --legacy

  SwapRouter02Executor 0xBe6d02FD9335C2e1e33bBC174ad7ee36764C8EE7


forge script script/DeployTrustedExclusiveDutch.s.sol:DeployTrustedExclusiveDutch  --fork-url hypercore --broadcast --legacy
  
  Reactor 0xA78FC86485BCF5C35fd4112d9BB922e05A8e3d41

forge script script/DeployHypercoreRouterExecutor.s.sol:DeployHypercoreRouterExecutor  --fork-url hypercore --broadcast --legacy

  HypercoreRouterExecutor 0xebd43e6AEfBb3D5a7411e3Cf0921e505d47f2840


BARE BONES TESTS:

forge test --match-path test/BareBones/ModuleRegistryRouter.t.sol
