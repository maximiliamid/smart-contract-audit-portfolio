# Smart Contract Audit Portfolio

Collection of smart contract audit exercises and historical DeFi hack replays.
Built with Foundry.

## Audit Contest Reports

### [2026-03 NFT Dealers](./2026-03-nft-dealers/) (CodeHawks First Flight #58)

NFT marketplace with progressive fee. **4 HIGH + 1 MED + 4 LOW findings**.

- **C-01**: `collectUsdcFromSelling` state-not-reset replay → drain contract
- **H-01**: `collateralForMinting` not reset → cross-resale double payment + DoS
- **H-02**: `uint32 price` caps marketplace at ~$4,294
- **H-03**: `cancelListing` refunds collateral without burning NFT → **free mint**
- **M-01**: `listingsCounter` vs `tokenId` mapping key mismatch

PoC: 4 Foundry tests PASS. See [FINDINGS.md](./2026-03-nft-dealers/FINDINGS.md).

### [2026-04 SNARKeling Treasure Hunt](./2026-04-snarkeling/) (First Flight #59)

ZK proof-based treasure hunt (Noir + Barretenberg Honk). **2 HIGH + 2 MED + 2 LOW findings**.

- **H-01**: `_treasureHash` typo in duplicate check → 1 proof drains 100 ETH
- **H-02**: Duplicate entry in `ALLOWED_TREASURE_HASHES`
- **M-01**: Plaintext secrets (1-10) leaked in Deploy script comment
- **M-02**: Public input `recipient` not constrained in Noir circuit

PoC: 2 Foundry tests PASS. See [FINDINGS.md](./2026-04-snarkeling/FINDINGS.md).

### [2026-02 Stratax](./2026-02-stratax-contracts/) (First Flight #57)

DeFi leveraged position protocol (Aave V3 + 1inch + Chainlink). **2 HIGH + 3 MED + 4 LOW findings**.

- **H-01**: Health factor threshold `> 1e18` too permissive (✅ mainnet fork PoC — HF 1.032, 311 bps buffer)
- **H-02**: `_call1InchSwap` return data decoding not robust for non-`swap()` functions (✅ PoC)
- **M-01**: `liqThreshold` not checked for zero → division panic (✅ PoC)
- **M-02**: Hardcoded 5% slippage too aggressive for liquid pairs
- **M-03**: Missing health factor check in unwind

**Mainnet fork PoC** confirmed 3 bugs on Aave V3 Ethereum (block 24,910,147):
```bash
ETH_RPC_URL=https://ethereum-rpc.publicnode.com \
  forge test --match-contract StrataxExploitPoC -vv
```

See [FINDINGS.md](./2026-02-stratax-contracts/FINDINGS.md).

## Practice Exercises

Warm-up challenges used to build the pattern library applied in the audit reports above.
See [`practice/README.md`](./practice/README.md) for the full list (6 Ethernaut levels + DVD Puppet variant reproducing the Mango Markets $117M pattern).

## Vulnerability Pattern Library

### Classic vulnerability classes
- [x] Reentrancy (CEI violation, cross-function, read-only)
- [x] Storage collision (proxy upgrade pattern)
- [x] Uninitialized immutable → wrong storage slot read
- [x] Duplicate constants / hardcoded values
- [x] Predictable randomness (blockhash, block.timestamp)
- [x] Constructor name typo (pre-0.5 historical)

### DeFi-specific
- [x] Spot price oracle manipulation
- [x] Flash loan + oracle manipulation
- [x] Oracle staleness / heartbeat gaps
- [x] State-not-reset payment replay
- [x] Cross-storage double spending
- [x] Type narrowing (uint32 price)
- [x] Health factor threshold too permissive

### ZK-specific
- [x] Public input binding (unused `pub` vars)
- [x] Verifier return data decoding
- [x] Secret leak in Deploy scripts
- [x] Low-entropy commitments

### UX/Integration
- [x] Mapping key mismatch (event emit vs storage)
- [x] `payable` without ETH handling
- [x] Missing zero-address validation
- [x] 2-step ownership transfer

## Tools & Framework

- **Foundry** (forge 1.5.1) — unit tests + fuzz tests + invariant tests
- **forge-std** — Vm cheatcodes for test isolation
- **Noir** (for ZK challenge) — SNARK circuit development

## Learning Resources

- [OpenZeppelin Ethernaut](https://ethernaut.openzeppelin.com) — 30+ CTF levels
- [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz) — 15+ DeFi pwn challenges
- [Solodit](https://solodit.xyz) — public audit findings aggregator
- [rekt.news](https://rekt.news) — DeFi hack post-mortems
- [CodeHawks First Flights](https://codehawks.cyfrin.io/first-flights) — entry-level contests
- [Code4rena](https://code4rena.com) — paid competitive audits
- [Sherlock](https://sherlock.xyz) — paid competitive audits
- [Immunefi](https://immunefi.com) — ongoing bug bounties

## Contact

- GitHub: [@maximiliamid](https://github.com/maximiliamid)
- Email: REDACTED

---

*This portfolio is developed as part of a transition into smart contract auditing. Each finding is benchmarked against public winning findings for severity calibration.*
