# Practice Challenges

Warm-up exercises used to build the vulnerability pattern library
applied in the main audit reports.

## Ethernaut Levels ([ethernaut.openzeppelin.com](https://ethernaut.openzeppelin.com))

| Level | Topic | Folder |
|---|---|---|
| 1 | Fallback — `receive()` abuse | [`level1-fallback/`](./level1-fallback/) |
| 2 | Fallout — historical constructor typo (pre-Solidity 0.5) | [`level2-fallout/`](./level2-fallout/) |
| 3 | Coin Flip — predictable blockhash randomness | [`level3-coinflip/`](./level3-coinflip/) |
| 10 | Re-entrance — CEI violation + `unchecked` drain | [`level10-reentrancy/`](./level10-reentrancy/) |
| 22 | Dex — spot-price oracle manipulation | [`level22-dex/`](./level22-dex/) |
| 24 | Puzzle Wallet — proxy storage collision (Wormhole-style) | [`level24-puzzle/`](./level24-puzzle/) |

## DeFi Hack Patterns

### [`dvd-puppet/`](./dvd-puppet/) — Damn Vulnerable DeFi "Puppet" variant

Flash loan + spot price oracle manipulation, reproducing the **Mango Markets $117M hack** pattern:

- Target Uniswap V1 pool: 10 ETH / 10 DVT (1:1)
- Lending pool: 100,000 DVT, requires 2x collateral
- Attacker starts with 25 ETH + 1,000 DVT
- Dumps DVT → spot price crashes → collateral requirement drops 10,000x
- Drains 100,000 DVT with only 19 ETH collateral

## Running tests

Each folder is a self-contained Foundry project:

```bash
cd <folder>
forge test -vv
```
