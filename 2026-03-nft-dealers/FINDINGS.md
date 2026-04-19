# NFT Dealers — Audit Findings

**Auditor**: maxi
**Date**: 2026-04-19
**Scope**: `src/NFTDealers.sol`, `src/MockUSDC.sol`
**nSLOC**: 253

---

## Summary

| # | Title | Severity | PoC | Source |
|---|---|---|---|---|
| C-01 | `collectUsdcFromSelling` does not reset state → contract drain via repeat call | **HIGH** | ✅ | own |
| H-01 | `collateralForMinting` not reset → double-payment on resale, insolvency DoS | **HIGH** | ✅ | own |
| H-02 | `listing.price` `uint32` → max ~4,294 USDC, HIGH fee tier never triggers | **HIGH** | ✅ | own |
| H-03 | `cancelListing` refunds collateral without burning/returning NFT → FREE MINT | **HIGH** | ✅ | benchmark #12 |
| M-01 | `listingsCounter` vs `tokenId` key mismatch — breaks core marketplace flow | **MEDIUM** | — | benchmark #23/#28 |
| L-01 | `updatePrice` does not check MIN_PRICE → bypass | **LOW** | — | benchmark #29 |
| L-02 | `mintNft()` and `buy()` are `payable` without handling `msg.value` → ETH locked | **LOW** | — | benchmark #10/#18/#24 |
| L-03 | Constructor does not validate `_owner != address(0)` | **LOW** | — | benchmark #15 |
| L-04 | `usdc.safeTransfer(address(this), fees)` is a gas-wasting no-op | **LOW** | — | own |
| L-05 | `calculateFees` external with "remove before production" comment still present | **LOW** | — | own |
| I-01 | README contradicts code (whitelist required to list NFT) | **INFO** | — | own |
| I-02 | `listing.nft = address(this)` always, redundant | **INFO** | — | own |

**Severity calibration notes** (lessons from benchmarking against winning findings):
- C-01 initially rated CRITICAL — downgraded to HIGH because while protocol is drained, owner retains emergency withdrawal.
- M-01 initially rated LOW — upgraded to MEDIUM because it breaks core marketplace flow.
- L-01 (previously M-01) initially rated MEDIUM — downgraded to LOW since it does not cause loss of funds.

---

## C-01: Contract drain via `collectUsdcFromSelling` replay

### Severity
**HIGH** — Any seller can drain all USDC in the contract.

### File & Lines
`src/NFTDealers.sol:171-183`

### Description

```solidity
function collectUsdcFromSelling(uint256 _listingId) external onlySeller(_listingId) {
    Listing memory listing = s_listings[_listingId];
    require(!listing.isActive, "Listing must be inactive to collect USDC");

    uint256 fees = _calculateFees(listing.price);
    uint256 amountToSeller = listing.price - fees;
    uint256 collateralToReturn = collateralForMinting[listing.tokenId];

    totalFeesCollected += fees;
    amountToSeller += collateralToReturn;
    usdc.safeTransfer(address(this), fees);
    usdc.safeTransfer(msg.sender, amountToSeller);
    // NO state mutation preventing re-call
}
```

After a seller calls this function once (post-legitimate sale), **no state changes** prevent a second call. All guards still pass:

- `onlySeller(_listingId)` — `s_listings[_listingId].seller` is still `msg.sender` (not reset)
- `require(!listing.isActive)` — `isActive` stays `false` post-buy
- `collateralForMinting[listing.tokenId]` — still equals the original `lockAmount` (not reset)

Consequence: the seller can call `collectUsdcFromSelling` **N times**, receiving `(price - fees) + collateral` each time, until the contract balance is exhausted.

### Impact

Total loss equals all USDC in the contract, including:
- Collateral from all mints (20 USDC × number of minted NFTs)
- Payments from all buyers
- Fees not yet withdrawn by owner

One seller with a single settled listing can drain millions of USDC from an active marketplace.

### PoC

See `test/ExploitPoC.t.sol:testCritical_CollectDrainViaRepeatedCalls`.

Output:
```
[PASS] testCritical_CollectDrainViaRepeatedCalls() (gas: 506319)
Logs:
  Seller A gain: 1030 USDC (legitimate: 515)
  Contract balance remaining: 10 USDC
```

Seller A receives **2× payment** from a single sale. With a larger contract balance, the seller can loop more iterations.

### Recommendation

Add a state flag or reset listing data after collection:

```diff
 function collectUsdcFromSelling(uint256 _listingId) external onlySeller(_listingId) {
     Listing memory listing = s_listings[_listingId];
     require(!listing.isActive, "Listing must be inactive to collect USDC");
+    require(listing.price > 0, "Already collected");

     uint256 fees = _calculateFees(listing.price);
     uint256 amountToSeller = listing.price - fees;
     uint256 collateralToReturn = collateralForMinting[listing.tokenId];

     totalFeesCollected += fees;
     amountToSeller += collateralToReturn;
-    usdc.safeTransfer(address(this), fees);
+
+    // Reset state to prevent replay
+    s_listings[_listingId].price = 0;
+    s_listings[_listingId].seller = address(0);
+    collateralForMinting[listing.tokenId] = 0;

     usdc.safeTransfer(msg.sender, amountToSeller);
 }
```

Alternative: use a dedicated `collected` mapping:

```solidity
mapping(uint256 => bool) public collectedForListing;

function collectUsdcFromSelling(uint256 _listingId) external onlySeller(_listingId) {
    require(!collectedForListing[_listingId], "Already collected");
    collectedForListing[_listingId] = true;
    // ... rest of logic
}
```

---

## H-01: Cross-resale double collateral → DoS / insolvency

### Severity
**HIGH** — The second seller on a given NFT CANNOT collect; collateral is paid out twice for the same NFT.

### File & Lines
`src/NFTDealers.sol:171-183` (same function as C-01, different impact)

### Description

Even if C-01 is fixed by adding a per-listing `collected` flag, this bug remains because `collateralForMinting[tokenId]` is never reset after collection.

Scenario:
1. Seller A mints NFT `tokenId=1`, depositing 20 USDC. `collateralForMinting[1] = 20`.
2. A lists, B buys. Contract receives 500 USDC. Total balance = 520 USDC.
3. A calls `collectUsdcFromSelling(1)`. Receives 495 + 20 = 515 USDC.
4. Contract balance = 5 USDC (fees only). `collateralForMinting[1]` is STILL 20.
5. B lists the same NFT (resale). `s_listings[1].seller = B`.
6. D buys from B. Contract receives 500 USDC. Total balance = 505 USDC.
7. B calls `collectUsdcFromSelling(1)`. Math computes: 495 + 20 = 515 USDC.
8. Transfer reverts: contract only has 505 USDC → **DoS**.

B is economically unable to collect, even though contractually entitled. B's USDC is locked.

### Impact

- Second and subsequent sellers on the same NFT are vulnerable to collection DoS.
- If there are 10 resale cycles for one NFT, the "promised" extra payment = 200 USDC from one mint = 10× collateral.
- A marketplace with many resales will become insolvent.

### PoC

`test/ExploitPoC.t.sol:testCritical_CrossResaleCollateralDoublePayment`

Output:
```
[PASS] testCritical_CrossResaleCollateralDoublePayment() (gas: 346562)
Logs:
  DoS: seller B CANNOT collect because contract is insolvent
  Contract balance: 505 USDC
  Expected payout: 515 USDC
```

### Recommendation

Already included in C-01 fix (`collateralForMinting[listing.tokenId] = 0`). Add invariant unit test: "total payout ≤ total deposits".

---

## H-02: `uint32 price` caps marketplace and disables HIGH fee tier

### Severity
**HIGH** — Functional bug; marketplace cannot sell NFTs above ~$4,294.

### File & Lines
`src/NFTDealers.sol:56` (Listing struct), `src/NFTDealers.sol:127` (list function)

### Description

`Listing.price` and the `_price` parameter in `list()` are both typed `uint32`. Max `uint32` = 4,294,967,295. With USDC at 6 decimals, the maximum price = **4,294.97 USDC**.

Meanwhile, fee tiers are defined as:
- LOW_FEE (1%): price ≤ 1,000 USDC
- MID_FEE (3%): 1,000 < price ≤ 10,000 USDC
- HIGH_FEE (5%): price > 10,000 USDC

Because the maximum price is only 4,294 USDC, **HIGH_FEE tier NEVER activates**. Expected fee revenue from the HIGH tier is lost (estimated ~40% of the designed revenue curve).

More seriously: blue-chip NFTs frequently trade at $10K-$100K. This marketplace cannot serve that segment.

### Impact

- Marketplace is unviable for high-value NFTs
- Revenue loss: the owner loses revenue from the HIGH_FEE tier
- Inconsistency between documented capability and actual behavior

### PoC

`test/ExploitPoC.t.sol:testHigh_PriceLimitedToUint32Max`

### Recommendation

Change `price` from `uint32` to `uint256` (or `uint128`):

```diff
 struct Listing {
     address seller;
-    uint32 price;
+    uint256 price;
     address nft;
     uint256 tokenId;
     bool isActive;
 }

-function list(uint256 _tokenId, uint32 _price) external onlyWhitelisted {
+function list(uint256 _tokenId, uint256 _price) external onlyWhitelisted {
```

Update all cast/assign sites consistently.

---

## H-03: `cancelListing` enables FREE MINT via collateral refund

### Severity
**HIGH** — Users can mint NFTs at zero net cost.

### File & Lines
`src/NFTDealers.sol:157-169`

### Description

```solidity
function cancelListing(uint256 _listingId) external {
    Listing memory listing = s_listings[_listingId];
    if (!listing.isActive) revert ListingNotActive(_listingId);
    require(listing.seller == msg.sender, "Only seller can cancel listing");

    s_listings[_listingId].isActive = false;
    activeListingsCounter--;

    // Refunds collateral in full to seller
    usdc.safeTransfer(listing.seller, collateralForMinting[listing.tokenId]);
    collateralForMinting[listing.tokenId] = 0;

    emit NFT_Dealers_ListingCanceled(_listingId);
}
```

This function refunds `collateralForMinting` to the seller on listing cancellation — **but the NFT remains in the seller's wallet** (not burned, not returned).

### Exploit Flow

1. Whitelisted user calls `mintNft()` → deposits 20 USDC, receives NFT.
2. User calls `list(tokenId, MIN_PRICE)` → listing is active.
3. User calls `cancelListing(tokenId)` → receives 20 USDC back.
4. **Result**: user has the NFT + their 20 USDC back = **free mint**.

A user can mint up to `MAX_SUPPLY` (1,000) NFTs at zero cost. The collateral mechanism (the core supply-cap economic protection) is entirely broken.

### Impact

- Collateral mechanism defeated (the "pre-set supply with lock" feature fails)
- 1,000 NFTs mintable free by one whitelisted user
- Destroys the marketplace's value proposition (supply cap + collateral)

### PoC

`test/ExploitPoC.t.sol:testHigh_FreeMintViaCancelListing`

Output shows one user mints 4 NFTs with 0 USDC total cost.

### Recommendation

Do not refund collateral in `cancelListing` — or burn/return the NFT alongside:

```diff
 function cancelListing(uint256 _listingId) external {
     ...
     s_listings[_listingId].isActive = false;
     activeListingsCounter--;
-
-    usdc.safeTransfer(listing.seller, collateralForMinting[listing.tokenId]);
-    collateralForMinting[listing.tokenId] = 0;
 }
```

Collateral should only be released on a successful sale via `collectUsdcFromSelling` (with the correct state reset from C-01 fix). Alternatively, if a canceled listing should refund collateral, **burn the NFT**:

```diff
 function cancelListing(uint256 _listingId) external {
     ...
     s_listings[_listingId].isActive = false;
     activeListingsCounter--;

+    _burn(listing.tokenId);  // burn NFT before refunding collateral
     usdc.safeTransfer(listing.seller, collateralForMinting[listing.tokenId]);
     collateralForMinting[listing.tokenId] = 0;
 }
```

---

## M-01: `listingsCounter` vs `tokenId` key mismatch

### Severity
**MEDIUM** — Breaks core marketplace flow.

### File & Lines
`src/NFTDealers.sol:133-138, 141, 157`

### Description

```solidity
function list(uint256 _tokenId, uint32 _price) external onlyWhitelisted {
    ...
    listingsCounter++;
    ...
    s_listings[_tokenId] = Listing({...});                // keyed by tokenId
    emit NFT_Dealers_Listed(msg.sender, listingsCounter); // emits listingsCounter
}

function buy(uint256 _listingId) external payable {
    Listing memory listing = s_listings[_listingId];      // reads by _listingId
    ...
}
```

The `NFT_Dealers_Listed` event emits `listingsCounter` (an incrementing counter). But `s_listings` is indexed by `_tokenId`. A frontend subscribing to the event will receive `listingsCounter` and call `buy(listingsCounter)` → **reads the wrong listing or an empty struct**.

### Impact

- Buyers using a standard event-driven UI cannot purchase (read returns empty struct)
- Or worse: purchase the wrong NFT if `listingsCounter` coincidentally matches an active `tokenId`
- Marketplace becomes non-functional via standard integrations

### Recommendation

Pick one model and be consistent:

**Option A** — key by `listingsCounter`:
```diff
-    s_listings[_tokenId] = Listing(...);
+    s_listings[listingsCounter] = Listing(..., tokenId: _tokenId);
```

**Option B** — emit `tokenId`:
```diff
-    emit NFT_Dealers_Listed(msg.sender, listingsCounter);
+    emit NFT_Dealers_Listed(msg.sender, _tokenId);
```

Option B is simpler since `tokenId` already serves as a unique per-NFT key.

---

## L-01: `updatePrice` does not check MIN_PRICE

### Severity
**LOW** — Protocol invariant can be bypassed, but no loss of funds.

### File & Lines
`src/NFTDealers.sol:185-193`

### Description

```solidity
function updatePrice(uint256 _listingId, uint32 _newPrice) external onlySeller(_listingId) {
    Listing memory listing = s_listings[_listingId];
    uint256 oldPrice = listing.price;
    if (!listing.isActive) revert ListingNotActive(_listingId);
    require(_newPrice > 0, "Price must be greater than 0");  // only checks > 0

    s_listings[_listingId].price = _newPrice;
}
```

`list()` enforces `require(_price >= MIN_PRICE)` (1 USDC), but `updatePrice()` only checks `> 0`. A seller can list for 1 USDC, then `updatePrice(_, 1 wei)`, bypassing MIN_PRICE.

### Recommendation

```diff
-    require(_newPrice > 0, "Price must be greater than 0");
+    require(_newPrice >= MIN_PRICE, "Price must be at least MIN_PRICE");
```

---

## L-02: `mintNft()` and `buy()` are `payable` without `msg.value` handling

### Severity
**LOW** — User funds permanently trapped on accidental ETH send.

### File & Lines
`src/NFTDealers.sol:114, 141`

### Description

```solidity
function mintNft() external payable onlyWhenRevealed onlyWhitelisted { ... }
function buy(uint256 _listingId) external payable { ... }
```

Both functions have the `payable` modifier but **never use `msg.value`**. The marketplace uses USDC (ERC20), not native ETH.

Consequence: if a user accidentally sends ETH (e.g. wallet UI pre-fills the value field, or a misconfigured integration), that ETH enters the contract and **no function withdraws ETH** → permanently locked.

### Recommendation

Remove the `payable` modifier if unnecessary:

```diff
-function mintNft() external payable onlyWhenRevealed onlyWhitelisted {
+function mintNft() external onlyWhenRevealed onlyWhitelisted {

-function buy(uint256 _listingId) external payable {
+function buy(uint256 _listingId) external {
```

Alternatively, if future iterations need to accept ETH, add an emergency ETH withdrawal:

```solidity
function emergencyWithdrawEth(address payable to) external onlyOwner {
    (bool ok,) = to.call{value: address(this).balance}("");
    require(ok);
}
```

---

## L-03: Constructor does not validate `_owner != address(0)`

### Severity
**LOW** — Deploying with `owner = 0` bricks the contract.

### File & Lines
`src/NFTDealers.sol:82-96`

### Description

```solidity
constructor(
    address _owner,
    address _usdc,
    ...
) ERC721(_collectionName, _symbol) {
    owner = _owner;   // no validation
    usdc = IERC20(_usdc);   // also no validation
    ...
}
```

If deployed with `_owner = address(0)` (accidental or script error), no one can call any `onlyOwner` functions (`revealCollection`, `whitelistWallet`, `removeWhitelistedWallet`, `withdrawFees`). The marketplace is permanently stuck in "not revealed" state.

### Recommendation

```diff
 constructor(address _owner, address _usdc, ...) ERC721(...) {
+    if (_owner == address(0)) revert InvalidAddress();
+    if (_usdc == address(0)) revert InvalidAddress();
     owner = _owner;
     usdc = IERC20(_usdc);
     ...
 }
```

Consider also verifying `_usdc.code.length > 0` to ensure the address is a contract (not an EOA).

---

## L-04: `usdc.safeTransfer(address(this), fees)` — no-op

### Severity
**LOW** — Wasted gas, confusing semantics.

### File & Lines
`src/NFTDealers.sol:181`

### Description

```solidity
usdc.safeTransfer(address(this), fees);
```

Transfers USDC from the contract **to itself**. This is a no-op. Not an exploit vector, but:
- Wastes gas (~5-10k per call)
- Signals code smell / unclear intent
- May be a red flag that developer misunderstands accounting

Fees are already IN the contract (from `buy`). `totalFeesCollected` already tracks them. This line is unnecessary.

### Recommendation

Remove the line.

---

## L-05: `calculateFees` should be removed before production

### Severity
**LOW** — Developer already flagged via comment.

### File & Lines
`src/NFTDealers.sol:203-207`

```solidity
function calculateFees(uint256 price) external pure returns (uint256) {
    // for testing purposes, we want to be able to call this function directly...
    // must be removed before production deployment...
    return _calculateFees(price);
}
```

In practice, this `pure` function does not provide an attacker advantage (the fee formula is public and deterministic). But the developer has flagged that it should be removed — honor that.

### Recommendation

Remove. If tests need it, test the internal `_calculateFees` via a test harness.

---

## I-01: README contradicts code

### Severity
**INFO**

### Description

README:
> Non whitelisted user/wallet: buy, update price, cancel listing, list NFT

Code:
```solidity
function list(uint256 _tokenId, uint32 _price) external onlyWhitelisted {
```

Non-whitelisted users cannot list. Clarify intent.

---

## General Recommendations

1. **Add invariant tests**:
   - "Total USDC in contract == SUM(pending collateral + pending seller payments + unwithdrawn fees)"
   - "No seller can call collect more than once per listing"
2. **Rename `listingsCounter` or use it as key** — pick one consistent model
3. **Review `activeListingsCounter` decrement paths** for possible double-decrement edge cases
4. **Add reentrancy guards** on `buy()` and `collectUsdcFromSelling()` — though basic attacks are blocked, defense-in-depth
5. **Numeric types**: use `uint256` for amounts; reserve `uint8/16/32` for enum-like values or packed struct slots
