# Hedgepie Contracts v2.1

##### HedgepieFinance is a Decentralized Yield Aggregator running on Binance Smart Chain (BSC), Ethereum & Polygon.

##### This is the main Hedgepie smart contract development repository for version 2.1.

<br/>

## Getting Started

### Requirements

-   [node v14](https://nodejs.org/download/release/latest-v14.x/)
-   [git](https://git-scm.com/downloads)
    <br/>

### Local Setup Steps 🔧

```sh
# Clone the repository
git clone https://github.com/innovation-upstream/hedgepie-dev
# Install dependencies
cd v2.1-contract && yarn install
# Set up environment variables (keys)
cp .env.example .env # (linux & mac)
copy .env.example .env # (windows)
# compile solidity, the below will automatically also run yarn typechain
yarn build
# test deployment, network: eth, bnb, polygon
yarn test:<network>
# yarn deploy:network <network>, example:
yarn deploy:network hardhat
```

<br/>

## Base Contracts

#### [HedgepieAccessControlled](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/HedgepieAccessControlled.sol)

#### [HedgepieAuthority](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/HedgepieAuthority.sol)

#### [HedgepieAdapterList](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/HedgepieAdapterList.sol)

#### [HedgepieYBNFT](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/HedgepieYBNFT.sol)

#### [HedgepieLibraryLib](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/libraries/HedgepieLibraryBsc.sol)

#### [PathFinder](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/PathFinder.sol)

#### [HedgepieInvestor](https://github.com/innovation-upstream/hedgepie-dev/blob/v2.1/v2.1-contract/contracts/base/HedgepieInvestor.sol)

<br/>

## Strategies

### BNB

-   AutoFarm
-   Beefy
-   Biswap
-   PancakeSwap

### Etherum

### Polygon
