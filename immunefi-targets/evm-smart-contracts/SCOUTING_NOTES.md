# Lombard Finance — Immunefi Scouting Notes

**Target**: https://immunefi.com/bug-bounty/lombard-finance/
**Max payout**: $250,000 (Critical)
**Focus per scope**: break 1:1 BTC peg, steal user funds
**Out of scope**: admin functions, notarization (consortium/, bascule/, Chainlink/LayerZero)

---

## Priority reading order (Week 1)

### Day 1-2: LBTC core — the token
- [ ] `contracts/LBTC/BaseLBTC.sol` (99 LOC) — base class
- [ ] `contracts/LBTC/StakedLBTC.sol` (577 LOC) — yield-bearing variant
- [ ] `contracts/LBTC/libraries/Assets.sol` (185 LOC) — asset accounting
- [ ] `contracts/LBTC/libraries/Validation.sol` (56 LOC) — input validation
- [ ] `contracts/LBTC/libraries/Redeem.sol` (23 LOC) — redemption paths
- [ ] `contracts/LBTC/libraries/Assert.sol` (46 LOC) — helper checks
- [ ] Search for LBTC.sol main token contract

**Questions to answer**:
- How is mint authorized? Which roles, which signatures?
- How is burn/redeem initiated and what validations?
- Is there a 1:1 invariant check on mint vs reserve?
- What happens on cross-chain message replay?

### Day 3-4: Bridge
- [ ] `contracts/bridge/Bridge.sol` (610 LOC)
- [ ] `contracts/bridge/BridgeV2.sol` (683 LOC)
- [ ] `contracts/bridge/adapters/AbstractAdapter.sol`
- [ ] `contracts/bridge/adapters/TokenPool.sol`
- [ ] `contracts/bridge/adapters/CLAdapter.sol` (Chainlink CCIP)
- [ ] `contracts/bridge/providers/LombardTokenPoolV2.sol`
- [ ] `contracts/bridge/oft/LBTCOFTAdapter.sol` (LayerZero OFT)

**Focus**: message replay, signature reuse across chains, nonce handling, fee calculation edge cases, rate limiting bypass.

### Day 5-7: Staking integrations
- [ ] `contracts/stakeAndBake/StakeAndBake.sol` (327 LOC)
- [ ] `contracts/stakeAndBake/StakeAndBakeNativeToken.sol` (349 LOC)
- [ ] `contracts/stakeAndBake/depositor/veda/ERC4626VaultWrapper.sol` (386 LOC)
- [ ] `contracts/stakeAndBake/depositor/veda/TellerWithMultiAssetSupportDepositor.sol`

**Focus**: permit2 handling, ERC4626 donation attacks, slippage checks, fee-on-transfer token handling.

---

## Vulnerability pattern checklist (apply to each contract)

### Token/accounting
- [ ] Mint auth: signature replay across chains, role abuse
- [ ] Peg invariant: is mintedLBTC == BTC collateral at all times?
- [ ] Rebasing / balance discrepancies if StakedLBTC has yield
- [ ] `permit()` signature reuse / replay
- [ ] `unchecked` blocks leading to underflow drain
- [ ] Fee-on-transfer token interaction

### Bridge
- [ ] Message replay: can same signed message be used twice?
- [ ] Cross-chain nonce: is it per-source-chain and unforgeable?
- [ ] Adapter callback trust: does adapter validate caller == bridge?
- [ ] CCIP gasLimit griefing (out-of-gas attacks)
- [ ] OFT composeMsg abuse

### Vault / staking
- [ ] First-depositor donation attack (inflate share price)
- [ ] ERC4626 rounding direction (favor vault, not user)
- [ ] Slippage config bypass
- [ ] Flash deposit-withdraw to drain fees
- [ ] Re-entrancy in deposit callback

### Standard list
- [ ] Reentrancy (cross-function, read-only, ERC777 hooks)
- [ ] Proxy storage collision (UUPS / Transparent)
- [ ] Missing access control / leaked privilege
- [ ] Chainlink oracle staleness / decimals mismatch
- [ ] CREATE2 salt collision / proxy factory bugs

---

## Deliverables

1. `SCOUTING_NOTES.md` — running notes (this file)
2. `findings/F-<num>-<title>.md` — one per hypothesis
3. `test/PoC/<Finding>.t.sol` — Foundry PoC for confirmed
4. Final `REPORT.md` — Immunefi submission format

---

## Realistic outcome

- 70-80% of hypotheses will NOT be real bugs (well-audited code)
- 1-2 confirmed High/Critical = the goal
- Time budget: 3 weeks solo, 2-3 hours/day
- If no confirmed bug after 3 weeks: pivot to next target, but keep learning log

## Immunefi submission format

Per https://immunefi.com/bug-bounty/lombard-finance/:
- Submit via Immunefi dashboard (not GitHub)
- Include: title, severity self-assessment, description, impact, steps to reproduce, PoC code
- Lombard team reviews + assigns severity
- Payout based on their severity rating (may differ from your assessment)
