# Option System

Smart contracts for Option Token (oToken) Liquidity Mining.

Read the [full developer documentation](https://docs.bondprotocol.finance/smart-contracts/option-system) at docs.bondprotocol.finance

## Background

Our mission [began as a paradigm shift](https://medium.com/@Bond_Protocol/introducing-bond-protocol-8476881f84e4) in the way protocols utilize emissions to acquire assets, own liquidity, and diversify their treasuries. Liquidity mining incentives are still, for better or worse, widely utilized in crypto to incentivize early network participants providing a valuable service - liquidity.

But incentives naturally attract short-term participants and [mercenary capital](https://www.nansen.ai/research/all-hail-masterchef-analysing-yield-farming-activity). Liquidity is also inherently temporary, a good mental model is that LM incentives "rent" liquidity.

**Re-contextualizing liquidity mining incentives as call options unlocks the ability for protocols to capture value and own their liquidity.**

This implementation draws inspiration from a number of sources including:

-   Andre Cronje - [Liquidity Mining Rewards v2](https://andrecronje.medium.com/liquidity-mining-rewards-v2-50896e44f259)
-   TapiocaDAO - [R.I.P Liquidity Mining](https://mirror.xyz/tapiocada0.eth/CYZVxI_zyislBjylOBXdE2nS-aP-ZxxE8SRgj_YLLZ0)
-   Timeless Finance - [Bunni oLIT](https://docs.bunni.pro/docs/tokenomics/olit)

## Overview

Bond Protocol's Option System is a flexible system for unlocking the power of Option Liquidity Mining (OLM) for projects of all sizes. We incorporated insights gained from bonding, notably designing a system that can be used with or without a price oracle.

### FixedStrikeOptionToken.sol

ERC20 implementation of a Fixed-Strike Option Token (oToken). When the token is created, strike price is set to a fixed exchange rate between two ERC20 tokens - the Payout and Quote tokens. oTokens inherit the units of the Payout token, and they are created 1:1. The Strike Price is provided in Quote token units and is formatted as the number of Quote tokens per Payout token. Timestamps are used to determine when the option is Eligible to be exercised and its Expiry, beyond which it cannot be exercised. The interplay between Eligible and Expiry times gives rise to the entire design space between American-style and European-style options.

![Lifecycle of an Option Token](./assets/Lifecycle%20of%20an%20oToken.png)

### FixedStrikeOptionTeller.sol

The Teller contract handles token accounting and manages interactions with end users exercising options. oTokens can be permissionlessly deployed and created by depositing the appropriate quantity of tokens as collateral. oTokens can be used as incentives via the OLM contracts, used within an existing ERC20 reward contract, or sold via a bond market (likely in an instant swap). Users can exercise their options by providing the appropriate quantity of tokens as payment alongside Eligible (but not Expired) oTokens. Exercised oTokens are burned after being provided to the Teller. After Expiry, the Receiver can reclaim collateral from unexercised options. Receivers can unwrap oTokens they possess at any time via the exercise function.

### OLM.sol

Option Liquidity Mining (OLM) implementation that manages option token rewards via an epoch-based system. OLM instances are deployed with immutable Staked Token (ex: LP token), Payout Token, and Option Teller addresses. Owners manage parameters used to create Option Tokens for a given epoch, as well as that epoch's duration and reward rate. Strike price can be set for the next epoch via a Manual implementation (only Owner) or based on a set discount from Oracle price. Once configured, Owners can enable deposits for LM. Owners can also withdraw Payout Tokens at any time.

Users can stake and unstake tokens at any time. An emergency unstake function is provided for edge cases, but users will forfeit all rewards if stake is withdrawn using this function. Rewards can be claimed for each eligible epoch. oTokens which have already expired are not claimed in order to save on gas costs.

New epochs can be triggered manually by the Owner, or they can be started when users call a function that tries to start a new epoch. If a user starts a new epoch, they are sent Option Tokens as the Epoch Transition Reward in order to compensate for increased gas cost paid.

### OLMFactory.sol

Factory contracts deploy instances of OLM contracts. The MOLMFactory deploys ManualStrikeOLM contracts, and the OOLMFactory deploys OracleStrikeOLM contracts. The sender of a deploy transaction is made the owner of the OLM contract. OLM contracts are not active when deployed. Owners must deposit rewards to the contract and then to call `initialize` to provide additional inputs and allow deposits.

## Design Decisions

In designing this system, we made a few opinionated decisions that differentiate it from other option protocols:

-   Our oTokens are Physically Settled, meaning that the underlying assets are actually exchanged when the option is exercised. This is in contrast to some systems which use Cash Settlement, where the difference in value from the strike price and the market price is exchanged in a separate unit of account asset when exercised. Traditional options markets often work on a cash settlement basis, but for protocols issuing options as rewards, physical settlement is superior since they often have large amounts of their native token and little "reserves".
-   Our initial oToken implementations use a fixed strike price determined when it is deployed instead of an oracle to track market price over time. Oracles are a challenging problem and are expensive to maintain. This means that many projects, especially new ones, do not have reliable oracles for their tokens. Liquidity mining is more common in early stage projects so it makes sense to build a system that is usable without an oracle. However, we recognize the convenience of reliable oracles and did make a version of the OLM contract which uses an oracle to set the fixed strike price at the beginning of each epoch. Our token + teller design can easily be extended to a true oracle-strike version in the future.
-   We sacrificed some fungibility of our oTokens by having each be unique to a receiver address in order to route proceeds from oToken exercises directly to the issuer (while providing them some flexibility on where these funds go). Our primary use case is not creating an exchange for options, and, therefore fungibility of the tokens was not the top priority. A future version may alter this part of the design to be more fungible.
-   Our oTokens have configurable eligible and expiry dates which allow for the creation of European options (only exercisable at the expiry), American options (exercisable any time from issuance up to expiry), or somewhere in between. Other options do not have expiries or implement one specific flavor.

## Getting Started

This repository uses Foundry as its development and testing environment. You must first [install Foundry](https://getfoundry.sh/) to build the contracts and run the test suite.

### Clone the repository into a local directory

```sh
$ git clone https://github.com/Bond-Protocol/options
```

### Install dependencies

```sh
$ cd options
$ npm install # install npm modules for linting
$ forge build # installs git submodule dependencies when contracts are compiled
```

## Build

Compile the contracts with `forge build`.

## Tests

Run the full test suite with `forge test`.

Fuzz tests have been written to cover certain input checks. Default number of runs is 4096.

## Linting

Pre-configured `solhint` and `prettier-plugin-solidity`. Can be run by

```sh
$ npm run lint
```

Run lint before committing.

### CI with Github Actions

Automatically run linting and tests on pull requests.

## Audits

The smart contracts in this repository were audited by Sherlock. The comprehensive audit report can be found in the `audit/` directory.

## License

The source code of this project is licensed under the [AGPL 3.0 license](LICENSE.md)

## Deployments

### Testnets

| Contract                | Address                                    | Goerli                                                                                             | Arbitrum Goerli                                                                                  |
| ----------------------- | ------------------------------------------ | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| RolesAuthority          | 0xa596f274CBDEF6e3A916D53E0B7AF8988119F343 | [Goerli Etherscan](https://goerli.etherscan.io/address/0xa596f274CBDEF6e3A916D53E0B7AF8988119F343) | [Goerli Arbiscan](https://goerli.arbiscan.io/address/0xa596f274CBDEF6e3A916D53E0B7AF8988119F343) |
| FixedStrikeOptionTeller | 0x5C9448c52760Be7E650380e3c635972E8182C6F4 | [Goerli Etherscan](https://goerli.etherscan.io/address/0x5C9448c52760Be7E650380e3c635972E8182C6F4) | [Goerli Arbiscan](https://goerli.arbiscan.io/address/0x5C9448c52760Be7E650380e3c635972E8182C6F4) |
| MOLMFactory             | 0xFd6A1211906E067C684725fBc665ec5EDea7d15A | [Goerli Etherscan](https://goerli.etherscan.io/address/0xFd6A1211906E067C684725fBc665ec5EDea7d15A) | [Goerli Arbiscan](https://goerli.arbiscan.io/address/0xFd6A1211906E067C684725fBc665ec5EDea7d15A) |
| OOLMFactory             | 0x92e2653Ec44BDe44a1EB35314550b9F81c81D6aF | [Goerli Etherscan](https://goerli.etherscan.io/address/0x92e2653Ec44BDe44a1EB35314550b9F81c81D6aF) | [Goerli Arbiscan](https://goerli.arbiscan.io/address/0x92e2653Ec44BDe44a1EB35314550b9F81c81D6aF) |

### Production
