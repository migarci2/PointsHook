# Points Hook (with Daily Cap)

A simple example of a Uniswap v4 **hook** that gives users reward points when they buy a token with ETH.

---

## Overview

* **When:** After every ETH → TOKEN swap.
* **Reward:** 20% of the ETH spent, in points.
* **Points type:** ERC-1155 tokens (each pool has its own token ID).
* **Daily cap:** Users can only earn up to `1e16` points per day per pool.

---

## How it works

1. The hook is attached to an ETH/TOKEN pool.
2. On every swap (ETH → TOKEN):

   * It checks how much ETH was actually spent using `BalanceDelta`.
   * It gives 20% of that amount as points.
   * It mints ERC-1155 tokens to the user.
   * Points stop minting once the daily limit is reached.
3. The cap resets every 24 hours.

---

## Getting the user address

The hook doesn't know who made the swap because `msg.sender` is the router.

Users must include their address in `hookData`:

```solidity
bytes memory hookData = abi.encode(address(user));
```

If the address is missing or invalid, no points are minted.

---

## Example logic

```solidity
uint256 ethSpent = uint256(int256(-delta.amount0));
uint256 points = ethSpent / 5; // 20%
_assignPoints(poolId, hookData, points);
```

The `_assignPoints` function keeps track of daily totals and enforces the cap.

---

## Key features

| Feature             | Description                          |
| ------------------- | ------------------------------------ |
| **afterSwap**       | Hook triggers after the swap is done |
| **ERC-1155 points** | Points per pool ID                   |
| **hookData**        | Contains the user address            |
| **Daily cap**       | Prevents abuse (max points per day)  |
| **Safe**            | Doesn’t change pool balances         |

---