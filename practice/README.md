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

### [`dvd-puppet/`](./dvd-puppet/) — Damn Vulnerable DeFi "Puppet" variant (simplified)

Flash loan + spot price oracle manipulation, reproducing the **Mango Markets $117M hack** pattern:

- Target Uniswap V1 pool: 10 ETH / 10 DVT (1:1)
- Lending pool: 100,000 DVT, requires 2x collateral
- Attacker starts with 25 ETH + 1,000 DVT
- Dumps DVT → spot price crashes → collateral requirement drops 10,000x
- Drains 100,000 DVT with only 19 ETH collateral

### [`damn-vulnerable-defi/`](./damn-vulnerable-defi/) — Official DVD v4.1

Forked from [theredguild/damn-vulnerable-defi](https://github.com/theredguild/damn-vulnerable-defi).
Solutions filled in for **16 of 18** challenges:

| Challenge | Pattern |
|---|---|
| Unstoppable | ERC4626 invariant bypass via direct transfer |
| Naive Receiver | Meta-tx `_msgSender()` spoofing via trusted forwarder + Multicall |
| Truster | Arbitrary `target.call` → approve attacker |
| Side Entrance | Flash loan + deposit back to credit attacker |
| The Rewarder | Merkle claim loop transfers each iteration, `_setClaimed` only on switch |
| Selfie | Flash loan governance tokens, queue emergency-exit action |
| Compromised | Leaked HTTP hex → base64 → oracle private keys, control median price |
| Puppet | Uniswap V1 spot-price oracle + ERC20 permit for 1-tx solve |
| Puppet V2 | Uniswap V2 spot-price oracle manipulation |
| Free Rider | Marketplace `msg.value` reused across buyMany loop + V2 flash swap |
| Backdoor | Safe `setup(to, data)` delegatecall injection → infinite approval |
| Climber | Timelock `execute` state check AFTER calls → schedule self mid-flight |
| Puppet V3 | Uniswap V3 TWAP with short window, mainnet fork (block 15450164) |
| ABI Smuggling | Hardcoded calldata offset bypass via non-standard bytes encoding |
| Wallet Mining | TransparentProxy.upgrader collides with AuthorizerUpgradeable.needsInit at slot 0 → re-init |
| Shards | fill() payment rounds to 0 while cancel() refund math ignores totalShards divisor |

Remaining (harder, open for later): Curvy Puppet (Curve stETH/ETH read-only reentrancy + mainnet fork), Withdrawal (cross-L2 message proof fraud analysis).

Run all solved:
```bash
cd practice/damn-vulnerable-defi
export MAINNET_FORKING_URL=https://rpc.mevblocker.io  # for Puppet V3
forge test --no-match-path "test/{curvy-puppet,withdrawal}/*"
```

## Running tests

Each folder is a self-contained Foundry project:

```bash
cd <folder>
forge test -vv
```
