# Domain Specialist Notes — Lombard Deep Dive

## LayerZero OFT patterns

### Known vulnerability classes
1. **Decimal conversion dust**: `decimalConversionRate = 10^(localDec - sharedDec)`. Default sharedDecimals = 6. Amounts below the rate get dust-truncated. For tokens with local decimals < 6, transfers always round to 0 → broken transfers.
2. **Compose message re-entry**: `lzCompose` on destination chain can be re-entered if target contract has exposed mutations.
3. **Peer configuration mismatch**: if source and destination use different OFT versions (OFT V1 vs V2), messages may decode wrong.
4. **Rate limit bypass via net design**: if inbound and outbound counters cross-offset, attacker bouncing tokens A→B→A can exceed per-direction limits.

### Applied to Lombard
- `LBTCBurnMintOFTAdapter.sol`: clean standard burn/mint. LBTC uses 8 decimals > 6 shared. No dust issue.
- `EfficientRateLimiter.sol`: implements net-bidirectional pattern **intentionally** per docs. Attacker can't bypass because each chain's limits still enforce per-direction caps; round-trip doesn't create new supply.
- No `lzCompose` handler — no compose surface.

## Veda Boring Vault patterns

### Known vulnerability classes
1. **Share inflation attack**: if vault has ratio `shares * totalAssets / totalSupply` and totalSupply is low, donation attack pumps share price → rounds user shares down to 0.
2. **Wrong approval target**: teller is call entry, but vault is puller. Approve the puller, not the teller.
3. **Bulk vs individual deposit**: `bulkDeposit` sends shares to `to` param; `deposit` sends to msg.sender. Mistakes in which variant is used = misdelivered shares.
4. **`beforeDeposit` hook re-entry**: Boring Vault allows custom before-hooks. Re-entry via ERC777-like tokens.

### Applied to Lombard
- `ERC4626VaultWrapper.sol`: override `_convertToShares` = identity (always 1:1). **Breaks inflation attack surface** because no ratio math. But also means wrapper doesn't capture vault yield — admin can pull it via `rescueERC20`.
- Approval is to `teller.vault()` (correct puller).
- Uses `teller.deposit` (to = msg.sender = wrapper), then wrapper re-mints 1:1 to user. Then `_checkAssetTotalBalance` enforces invariant `totalSupply ≤ totalAssets`.
- `TellerWithMultiAssetSupportDepositor.sol` uses `teller.bulkDeposit(..., owner)` — shares go directly to owner, wrapper doesn't hold them.

## Rate limiter implementation patterns

### Known vulnerability classes
1. **Integer underflow when opposite counter < current amount** — need unchecked block with conditional.
2. **`lastUpdated` freeze**: if an operation doesn't update lastUpdated, the decay calculation uses stale timestamp.
3. **Window edge cases**: at `now == lastUpdated + window`, should counter reset?

### Applied to Lombard
- `_checkAndUpdateRateLimit`: uses `unchecked` with ternary for opposite direction (line 227-231). Safe.
- `_setRateLimits` updates opposite direction's `lastUpdated` without decaying — subtle but likely intentional for checkpoint semantics.
- No edge case bug confirmed.

## BridgeV2 GMP patterns

### Known vulnerability classes
1. **Message replay across chains**: if nonce is per-chain but not keyed by (srcChain, nonce), cross-chain replay.
2. **Path misconfiguration**: asymmetric bidirectional routing — destination might accept messages from wrong source.
3. **`functionCallWithValue` on destination**: if destination allows arbitrary contract call, access checks critical.

### Applied to Lombard
- `payloadSpent[payload.id]` prevents double-spend per-payload.
- `chainId` from `mailbox.getInboundMessagePath` — authoritative source chain.
- `payload.msgSender != sourceBridge` rejects forged messages.
- `_withdraw` checks `allowedDestinationToken[keccak(srcChain | token)]` — bidirectional registration assumption; needs deployment verification but protocol defensively correct.

## Conclusion (honest)

After domain-specialist review of ~2,000 LOC across 4 major modules:
- **No confirmed bugs**
- **No plausible high-severity hypotheses that survive scrutiny**
- Protocol is well-architected with multiple defense layers

Unexplored areas where bugs might still exist:
- BridgeV2 full walkthrough (683 LOC) including adapters (CCIP, LayerZero)
- Proxy upgrade paths (storage collision across 4+ initializable contracts)
- IBCVoucher (~200 LOC) — IBC-specific patterns
- PMM wrappers (BTCB/CBBTC) — BTC bridge integrations

Time estimate for full scope review: **40-60 hours** by a generalist auditor,
**10-20 hours** by a LayerZero/Veda specialist.
