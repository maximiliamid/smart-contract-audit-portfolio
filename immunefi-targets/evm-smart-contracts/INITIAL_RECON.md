# Lombard Finance — Initial Recon Notes

Pass 1 over core contracts. NOT confirmed findings yet — these are hypotheses
to validate with deeper analysis + PoC construction.

---

## Observations from NativeLBTC.sol

### H-1? Fee-approval signature replay across multiple mints
**File**: `contracts/LBTC/NativeLBTC.sol:313-320`

```solidity
function mintV1WithFee(
    bytes calldata mintPayload,
    bytes calldata proof,
    bytes calldata feePayload,
    bytes calldata userSignature
) external onlyRole(CLAIMER_ROLE) {
    _mintWithFee(mintPayload, proof, feePayload, userSignature);
}
```

User signs `feePayload` with `(fee, expiry)`. The signature is checked via
`Assert.feeApproval(digest, recipient, userSignature)`. **There is no nonce
or anti-replay for `feePayload`** — same fee signature can be reused across
different mint payloads until `expiry`.

**Assessment**: `onlyRole(CLAIMER_ROLE)` restricts to trusted admin role.
Per Immunefi scope, admin abuse is out of scope. **SKIP** unless CLAIMER is
proven to be a shared/compromised role.

### H-2? MSG_VERSION decoded but not validated in `decodeMsgBody`
**File**: `contracts/bridge/BridgeV2.sol:558-578`

Assembly decodes `version := byte(0, ...)` at line 572 but the value is
never checked against `MSG_VERSION = 1`. If a future source chain sends a
higher-version message, current destination accepts it silently.

**Assessment**: LOW impact — only matters during multi-version rollout.
Still worth reporting as defense-in-depth finding. Severity: Low/Info.

### H-3? `_withdraw` validates with `allowedDestinationToken` on receive side
**File**: `contracts/bridge/BridgeV2.sol:524-550`

```solidity
if ($.allowedDestinationToken[_calcAllowedTokenId(chainId, GMPUtils.addressToBytes32(token))] == bytes32(0))
    revert BridgeV2_TokenNotAllowed();
```

On the **receive** side, `chainId` is the source chain (not destination).
Meanwhile `allowedDestinationToken` is keyed by `(destinationChain, sourceToken) → destinationToken`.

This assumes the bridge registers **bidirectional paths** on each chain
(remoteChain | localToken → remoteToken). Needs verification that this holds
for all live pathways — if not, `_withdraw` may accept messages from
unregistered source-chain pairs.

**Needs**: cross-check `addDestinationToken` on-chain state vs what's
registered on destination chain. Could be a real bug if registration
asymmetric.

### H-4? `_burnToken` pattern + fee-on-transfer integration
**File**: `contracts/bridge/BridgeV2.sol:452-456`

```solidity
SafeERC20.safeTransferFrom(token, _msgSender(), address(this), amount);
token.burn(amount);
```

For fee-on-transfer tokens, bridge receives `amount - fee` but burns
`amount` — reverts. Not applicable to LBTC (no fee), but if protocol lists
fee-on-transfer tokens via `addDestinationToken`, this path breaks.

**Assessment**: Depends on token list. Probably SKIP for LBTC scope.

### H-5? Rate limit bypass via multi-path
**File**: `contracts/bridge/BridgeV2.sol:540-545, libs/RateLimits.sol`

Rate limit keyed by `(sourceChain | token)`. If LBTC has multiple bridge
pathways (different GMP providers), each registers a separate bridge
contract. But rate limit is per source chain — so a single sourceChain with
multiple pathways shares one rate limit.

**However** — different adapters (CCIP, LayerZero) may go through different
BridgeV2 instances or single instance? Need to check deployment topology.
If one BridgeV2 handles all adapters, rate limit works. If multiple
BridgeV2s exist per provider, the budget is multiplied.

**Needs**: verify mainnet deployment architecture.

### H-6? Proxy upgrade path (ProxyFactory.sol)
**File**: `contracts/factory/ProxyFactory.sol`

Not yet read. UUPS/Transparent proxy factory — prime place for storage
collision / init race.

**Next action**: read ProxyFactory + any initializable contract deployed
through it.

---

## Next reading queue

- [ ] `contracts/LBTC/StakedLBTC.sol` (577 LOC) — ERC4626 patterns, yield
- [ ] `contracts/LBTC/AssetRouter.sol` — routes mint/burn between LBTC variants
- [ ] `contracts/LBTC/StakedLBTCOracle.sol` — price oracle mechanics
- [ ] `contracts/stakeAndBake/StakeAndBake.sol` (327 LOC)
- [ ] `contracts/stakeAndBake/depositor/veda/*` — Veda/Boring Vault integration
- [ ] `contracts/ibc/IBCVoucher.sol` — IBC message handling
- [ ] `contracts/factory/ProxyFactory.sol`
- [ ] `contracts/pmm/*` — BTCB/CBBTC wrappers

## Audit mindset reset (important)

**Realistic outcome for this target**:
- 40-80 hours deep analysis across 3 weeks
- 60-80% hypotheses won't pan out
- Goal: 1 validated HIGH/CRITICAL = $25K-$250K payout
- Focus: peg break OR user-fund-steal (per Immunefi scope)

**Skip**:
- Admin-controlled functions (role changes, fee configs)
- Notarization logic (consortium/, bascule/ — out of scope)
- Known-good patterns (OZ upgradeable, standard ERC20 with audited impl)

**Prioritize**:
- Custom invariants (peg, balance tracking, fee accounting)
- Cross-chain edge cases (message ordering, nonce collision, replay)
- Integration points (deposit adapters, swap routers)
- Storage collision in proxy deployments
