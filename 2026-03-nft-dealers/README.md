# NFT Dealers

- Starts: March 12, 2026 Noon UTC
- Ends: March 19, 2026 Noon UTC

- nSLOC: 253

[//]: # (contest-details-open)

## About the Project

NFT Dealers is a NFT marketplace with pre-set supply, and resell option with `Progressive fee` 1, 3 or 5%.
Collecting base price/collateral on minting. NFTs can be sold by users on any price, but the fee will grow with the resell price.
Can be used for in-game events, ticketing system, no limited to any specific purpose.


```
The protocol have 2 phases:
1. Preparation phase. The protocol is deployed but not `revealed`, before revealing few things can be done:
- owner whitelists wallets that can mint NFTs

2. The protocol is `revealed`:
- whitelisted users can mint NFTs
- users that are whitelisted can now list NFTs for secondary sell.
- users can buy from listings
- owner can withdraw fees
- owner can remove wallets from whitelist at any time.
```

## Actors

```
There are 3 types of actors in the protocol:

Actors:

1. Owner
- deploy the smart contract and set parameters (collateral, collection name, image, symbol, etc.)
- whitelist or remove from whitelist wallets
- `reveal` the protocol
- withdraw fees

2. Whitelisted user/wallet
- mint NFT
- buy, update price, cancel listing, list NFT
- collect USDC after selling

3. Non whitelisted user/wallet
- cannot mint
- buy, update price, cancel listing, list NFT
- collect USDC after selling
```

[//]: # (contest-details-close)

[//]: # (scope-open)

## Scope (contracts)
```js
src/
├── MockUSDC.sol
├── NFTDealers.sol

```

## Compatibilities

```
Compatibilities:
  Blockchains:
      - Ethereum/Any EVM
  Tokens:
      - ERC20 (USDC only)
      - ERC721 
```

[//]: # (scope-close)

[//]: # (getting-started-open)

## Setup

Build:
```bash
git clone https://github.com/CodeHawks-Contests/2026-03-NFT-dealers.git

forge install 

forge build
```

Tests:
```bash
forge test
```

[//]: # (getting-started-close)

[//]: # (known-issues-open)

## Known Issues

N/A

[//]: # (known-issues-close)
