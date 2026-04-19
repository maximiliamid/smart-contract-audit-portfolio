# Stratax

- Starts: February 12, 2026
- Ends: February 19, 2026

- nSLOC: 356

[//]: # "contest-details-open"

## About the Project

Stratax is a DeFi leveraged position protocol that enables users to create leveraged exposure to crypto assets using Aave V3 lending pools and 1inch DEX aggregator. The protocol uses flash loans to achieve capital-efficient leverage without requiring users to manually manage complex borrowing and swapping operations.

Key Features:

- Leveraged position creation using Aave V3 flash loans
- Automated position unwinding with debt repayment
- Integration with 1inch for optimal swap execution
- Chainlink oracle integration for accurate price feeds

The protocol allows users to specify their desired leverage (e.g., 3x) and collateral amount, then automatically:

1. Takes a flash loan for additional capital
2. Supplies total collateral to Aave
3. Borrows against the collateral
4. Swaps borrowed tokens back to collateral token
5. Repays the flash loan
6. Result is a leveraged position held by the Stratax contract

## Actors

**Position Owner :**

- Powers: Can create leveraged positions, unwind positions, supply additional collateral, withdraw collateral, borrow debt tokens, and repay debt
- Limitations: Cannot perform operations that would make the position unhealthy (health factor < 1)
- The owner of the Stratax contract owns all the tokens and Aave positions within the contract

**Oracle Owner:**

- Powers: Can set and update Chainlink price feeds for supported tokens
- Limitations: Can only set price feeds with 8 decimals precision

[//]: # "contest-details-close"
[//]: # "scope-open"

## Scope (contracts)

```
All Contracts in `src` are in scope.
```

```js
src/
├── Stratax.sol
└── StrataxOracle.sol
```

### Stratax.sol (293 nSLOC)

Core protocol contract managing leveraged positions using Aave V3 flash loans and 1inch swaps. Key functionality:

- Creating leveraged positions via flash loans
- Unwinding positions back to original collateral
- Calculating optimal leverage parameters (including backward calculation from desired leverage)
- Managing position health and collateral
- Integration with Aave V3 pool for flash loans, supplies, and borrows
- Integration with 1inch for collateral ↔ debt token swaps

### StrataxOracle.sol (63 nSLOC)

Chainlink price oracle integration for position valuation. Key functionality:

- Managing token → Chainlink price feed mappings
- Retrieving token prices with 8 decimal precision
- Restricting Stratax to only supported tokens

## Compatibilities

**Blockchains:**

- Ethereum Mainnet (primary target)
- All EVM-compatible chains with Aave V3, 1inch, and Chainlink deployed

**Tokens:**

- ERC20 tokens supported by Aave V3 (as collateral or debt assets)
- Tokens with Chainlink price feeds (8 decimal precision required)
- Standard ERC20 implementation (no fee-on-transfer, rebasing, or exotic mechanics)
- Tokens supported by 1inch DEX aggregator on the target chain

**External Protocol Requirements:**

- Aave V3 Pool contract
- 1inch AggregationRouterV5
- Chainlink AggregatorV3Interface price feeds

[//]: # "scope-close"
[//]: # "getting-started-open"

## Setup

System requirements: Node.js and Foundry

Build:
Clone the repo and navigate to project root:

```bash
npm install

forge install OpenZeppelin/openzeppelin-contracts-upgradeable

forge build
```

Tests:

NOTE: `.env` is required and look at example.env file for reference. For the eth RPC URL use a good one that can fork old block numbers. Lastly, the 1Inch API is recommended, but not necessary. If the 1inch API key is not present the test will use saved swap data for a past block.

NOTE: `ffi` is enabled in foundry.toml to generate 1inch swap data.

```bash
forge test
```

[//]: # "getting-started-close"
[//]: # "known-issues-open"

## Known Issues

None

[//]: # "known-issues-close"
