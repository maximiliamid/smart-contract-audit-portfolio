# SNARKeling Treasure Hunt — Audit Findings

**Auditor**: maxi
**Date**: 2026-04-19
**Scope**: `contracts/src/TreasureHunt.sol`, `contracts/scripts/Deploy.s.sol`, `circuits/src/main.nr`
**nSLOC**: ~220

---

## Summary

| # | Title | Severity |
|---|---|---|
| H-01 | `_treasureHash` typo disables duplicate-check → 1 proof drains 100 ETH | **HIGH** |
| H-02 | Duplicate entry in `ALLOWED_TREASURE_HASHES` locks 1 treasure + enables replay | **HIGH** |
| M-01 | Plaintext secrets (1-10) leaked in `Deploy.s.sol` comment + low entropy | **MEDIUM** |
| M-02 | Public input `recipient` not constrained in the Noir circuit | **MEDIUM** |
| L-01 | `receive()` accepts ETH from anyone, bypassing `fund()` authorization | **LOW** |
| L-02 | `updateVerifier` does not validate that address is a contract | **LOW** |
| I-01 | `msg.sender != recipient` check trivially bypassable via contract intermediary | **INFO** |

---

## H-01: `_treasureHash` typo disables duplicate-check

### Severity
**HIGH** — Direct loss of funds; the entire 100 ETH is drainable with a single valid proof.

### File & Lines
`contracts/src/TreasureHunt.sol:88`

### Description

The `claim()` function performs the duplicate-check by reading the `claimed` mapping at the **wrong key**:

```solidity
// Line 35 — immutable that is never assigned in constructor
bytes32 private immutable _treasureHash;

// Line 88 — wrong read
if (claimed[_treasureHash]) revert AlreadyClaimed(treasureHash);
//            ^^^^^^^^^^^^^^                      ^^^^^^^^^^^^^
//            uninitialized                       correct parameter
```

Because `_treasureHash` is an `immutable` that is never assigned in the constructor, its value is always `bytes32(0)`. The slot `claimed[bytes32(0)]` is never written by `_markClaimed(treasureHash)` (which uses the correct parameter), so this check **never** triggers a revert.

### Impact

Anyone holding **one valid proof** for a `(treasureHash, recipient)` pair can replay the same transaction up to `MAX_TREASURES` (10) times. Each claim transfers 10 ETH reward → total **100 ETH drainable**.

### PoC

`contracts/test/ExploitPoC.t.sol:testCritical_ReplayDueToWrongStorageSlot`

```solidity
bytes memory proof = hex"42abcdef"; // one valid proof
bytes32 treasureHash = keccak256("treasure_1");

for (uint256 i = 0; i < 10; i++) {
    hunt.claim(proof, treasureHash, payable(recipient));
}

assertEq(recipient.balance, 100 ether);
assertEq(address(hunt).balance, 0);
```

Output:
```
[PASS] testCritical_ReplayDueToWrongStorageSlot() (gas: 341152)
```

### Recommendation

Replace `_treasureHash` with the parameter `treasureHash`:

```diff
-   if (claimed[_treasureHash]) revert AlreadyClaimed(treasureHash);
+   if (claimed[treasureHash]) revert AlreadyClaimed(treasureHash);
```

Also remove the unused `bytes32 private immutable _treasureHash;` declaration.

Add a regression test asserting that a second claim for the same `treasureHash` **reverts**.

---

## H-02: Duplicate entry in `ALLOWED_TREASURE_HASHES`

### Severity
**HIGH** — Permanent loss of access and, when combined with H-01, a double-drain vector.

### File & Lines
`circuits/src/main.nr:64-65`

### Description

The `ALLOWED_TREASURE_HASHES` array has two identical final entries:

```noir
global ALLOWED_TREASURE_HASHES: [Field; 10] = [
    ...,
    -961435057317293580094826482786572873533235701183329831124091847635547871092,  // index 8
    -961435057317293580094826482786572873533235701183329831124091847635547871092   // index 9 — DUPLICATE
];
```

Compare against `Deploy.s.sol:25-26`:

```
-4417726114039171734934559783368726413190541565291523767661452385022043124552,  // should be index 8
-961435057317293580094826482786572873533235701183329831124091847635547871092    // should be index 9
```

This means the treasure with hash `-4417726114039171734934559783368726413190541565291523767661452385022043124552` **cannot be proven valid by the circuit**, because it does not appear in `ALLOWED_TREASURE_HASHES`.

### Impact

1. The 10 ETH reserved for treasure #8 is **permanently locked** (no valid proof will ever exist for the correct hash). Owner can still use `emergencyWithdraw` while paused, but the normal `withdraw()` requires `claimsCount >= MAX_TREASURES`, which will never happen.

2. Combined with H-01, an attacker who finds treasure #10 (whose hash appears twice in the array) can:
   - Generate a valid proof for `hash_10`
   - Replay the proof via H-01 to drain all funds
   - All with a single proof

3. The protocol invariant is violated: "10 unique treasures" is actually only 9.

### Recommendation

Replace index 9 with the correct hash from `Deploy.s.sol`:

```diff
global ALLOWED_TREASURE_HASHES: [Field; 10] = [
    ...
    -961435057317293580094826482786572873533235701183329831124091847635547871092,
-   -961435057317293580094826482786572873533235701183329831124091847635547871092
+   -4417726114039171734934559783368726413190541565291523767661452385022043124552
];
```

Add a unit test in `circuits/src/tests.nr` asserting uniqueness of all 10 hashes:

```noir
#[test]
fn test_all_hashes_unique() {
    for i in 0..10 {
        for j in (i+1)..10 {
            assert(ALLOWED_TREASURE_HASHES[i] != ALLOWED_TREASURE_HASHES[j]);
        }
    }
}
```

---

## M-01: Plaintext secrets leaked in Deploy comment + low entropy

### Severity
**MEDIUM** — Breaks the product premise (anyone can claim without physically finding a treasure).

### File & Lines
`contracts/scripts/Deploy.s.sol:14-15`

### Description

```solidity
// Secret Treasures for the snorkeling hunt (not revealed to the public):
//      1, 2, 3, 4, 5, 6, 7, 8, 9, 10
```

A comment in the deployment script, published in the public repo, reveals that the secret treasures are the integers 1-10. These look like the Field element values used in the Noir circuit.

Even if the comment were removed, the secret space `{1, 2, ..., 10}` has entropy **~3.32 bits** (`log2(10)`) — brute-forceable in 10 Pedersen hash computations.

### Impact

1. The protocol's foundation (that someone must physically find a treasure to generate a proof) **completely fails**.
2. Any attacker can:
   - Compute `pedersen_hash(i)` for `i = 1..10`
   - Match against `ALLOWED_TREASURE_HASHES`
   - Generate a valid proof for every treasure
   - Claim all 10 rewards without ever touching water

### Recommendation

1. Remove the comment exposing the secrets.
2. Use secrets with high entropy (≥128 bits) — e.g., random `bytes32`, not small integers.
3. Generate and distribute secrets off-chain; do not hardcode in the deploy script.
4. Consider additional binding such as `treasure_id || random_nonce`.

---

## M-02: Public input `recipient` not constrained in the Noir circuit

### Severity
**MEDIUM** — Dependent on specific Barretenberg Honk backend behavior; potential proof malleability.

### File & Lines
`circuits/src/main.nr:28-39`

### Description

```noir
fn main(treasure: Field, treasure_hash: pub Field, recipient: pub Field) {
    assert(is_allowed(treasure_hash));
    assert(std::hash::pedersen_hash([treasure]) == treasure_hash);
    // Noir enforces constraints on the public inputs,
    // so we don't need an explicit check for recipient format here.
    // The "unused variable" warning should be ignored.
}
```

`recipient` is declared as `pub` but **is never used in any constraint**. The developer's comment asserts that `pub` alone is sufficient for binding — this assumption needs verification.

In many ZK frameworks, public inputs are committed to in the proof (so the verifier can check values). BUT without a constraint that uses the variable, the compiler may:
- Emit an "unused variable" warning
- Optimize the variable away (depending on compiler settings)
- Still include it in the public commitment (safer behavior)

This behavior is backend-specific. Without an explicit confirmation test, relying on implicit binding is a **ZK anti-pattern**.

### Potential Impact

If `recipient` is in fact not bound to the proof:
- An attacker can take any valid proof from the mempool
- Resubmit it with `recipient = attacker_address`
- Steal the reward from the original claimant

This would destroy the "replay-resistance through recipient binding" property documented in the README.

### Recommendation

Add an explicit constraint using `recipient`:

```noir
fn main(treasure: Field, treasure_hash: pub Field, recipient: pub Field) {
    assert(is_allowed(treasure_hash));
    assert(std::hash::pedersen_hash([treasure]) == treasure_hash);

    // Bind recipient explicitly — hash with treasure_hash so the proof
    // is genuinely dependent on the recipient value.
    let _binding = std::hash::pedersen_hash([treasure_hash, recipient]);
    assert(_binding == _binding); // no-op but forces compiler to retain variable
}
```

Stronger: include `recipient` in the provable statement (e.g., `assert(recipient != 0)`).

Write a test that verifies a proof generated with `recipient_A` **reverts** when submitted with `recipient_B` in `publicInputs`.

---

## L-01: `receive()` bypasses `fund()` authorization

### Severity
**LOW** — No loss of funds, but inconsistent authorization.

### File & Lines
`contracts/src/TreasureHunt.sol:236-241, 287-289`

### Description

```solidity
function fund() external payable {
    require(msg.sender == owner, "ONLY_OWNER_CAN_FUND");  // checked
    ...
}

receive() external payable {
    emit Funded(msg.value, address(this).balance);        // not checked
}
```

`fund()` restricts who can add funds, but `receive()` accepts ETH from anyone via plain transfer, **bypassing that check**.

### Impact

- No loss of funds
- Off-chain accounting may get confused (`Funded` event emitted from non-owner)
- Signals a broader inconsistency in authorization patterns

### Recommendation

Pick one:
1. Remove the restriction in `fund()` (let anyone fund — consistent with `receive()`)
2. Or `revert()` in `receive()` and keep the owner-only `fund()`

---

## L-02: `updateVerifier` does not validate contract

### Severity
**LOW** — Temporary DoS, reversible.

### File & Lines
`contracts/src/TreasureHunt.sol:263-269`

### Description

```solidity
function updateVerifier(IVerifier newVerifier) external {
    require(paused, "THE_CONTRACT_MUST_BE_PAUSED");
    require(msg.sender == owner, "ONLY_OWNER_CAN_UPDATE_VERIFIER");
    verifier = newVerifier;
}
```

No validation that `newVerifier` has bytecode. If set to an EOA:
- `verifier.verify(...)` succeeds (call to EOA = no-op)
- Return data is empty, decoding to bool gives `false`
- Every `claim()` reverts with `InvalidProof` → DoS

Also, no `newVerifier != address(0)` check like the constructor has.

### Recommendation

```solidity
require(address(newVerifier) != address(0), "InvalidVerifier");
require(address(newVerifier).code.length > 0, "NotAContract");
```

Ideally also run a dummy call to confirm the verifier responds correctly.

---

## I-01: `msg.sender != recipient` trivial bypass

### Severity
**INFO** — Questionable design.

### File & Lines
`contracts/src/TreasureHunt.sol:86`

### Description

```solidity
if (recipient == ... || recipient == msg.sender) revert InvalidRecipient();
```

The intent to prevent a claimant from paying themselves is unclear. An attacker can:
- Deploy contract `A`
- Implement `A.forward(address payable receiver)` to forward incoming ETH to receiver (attacker)
- Claim with `recipient = address(A)`, `msg.sender = attacker EOA`

Trivially bypassable; adds complexity without security benefit.

### Recommendation

Review whether this check is actually needed. If yes, document the specific threat it mitigates. If not, remove it.

---

## General Recommendations

1. **Add unit tests for each invariant**: "same treasureHash can only be claimed once", "total claims ≤ 10", "proof is bound to recipient".
2. **Use `forge coverage`** to ensure all paths are covered.
3. **Rename / remove storage variables**: unused `_treasureHash` is a code smell that linters/compilers should catch.
4. **Treat ZK binding explicitly**: every public input intended for binding must have an explicit constraint.
5. **Never hardcode secrets** in the repo, even in "example" comments.
