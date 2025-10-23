// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC1155} from "solmate/src/tokens/ERC1155.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

library PointsHookPerms {
    function permissions() internal pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize:  false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity:  false,
            afterRemoveLiquidity:false,
            beforeSwap: false,
            afterSwap:  true,
            beforeDonate: false,
            afterDonate:  false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta:  false,
            afterAddLiquidityReturnDelta:    false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}

contract PointsHook is BaseHook, ERC1155 {
    struct DayAccrual {
        uint64 day;
        uint192 minted;
    }

    uint256 public constant DAILY_CAP_POINTS = 1e16;

    mapping(address => mapping(bytes32 => DayAccrual)) public dailyAccrual;

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    // Set up hook permissions to return `true`
    // for the two hook functions we are using
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return PointsHookPerms.permissions();
    }

    // Implement the ERC1155 `uri` function
    function uri(uint256) public view virtual override returns (string memory) {
        return "https://api.example.com/token/{id}";
    }

    function _today() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    function _assignPoints(PoolId poolId, bytes calldata hookData, uint256 points) internal {
        if (hookData.length == 0 || points == 0) return;

        address user = abi.decode(hookData, (address));
        if (user == address(0)) return;

        bytes32 pid = PoolId.unwrap(poolId);
        DayAccrual storage acc = dailyAccrual[user][pid];
        uint64 today = _today();

        if (acc.day != today) {
            acc.day = today;
            acc.minted = 0;
        }

        if (acc.minted >= DAILY_CAP_POINTS) return;

        uint256 remaining = DAILY_CAP_POINTS - acc.minted;
        uint256 mintNow = points > remaining ? remaining : points;
        if (mintNow == 0) return;

        uint256 poolIdUint = uint256(pid);
        _mint(user, poolIdUint, mintNow, "");

        unchecked {
            acc.minted += uint192(mintNow);
        }
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // If this is not an ETH-TOKEN pool with this hook attached, ignore
        if (!key.currency0.isAddressZero()) return (this.afterSwap.selector, 0);

        // We only mint points if user is buying TOKEN with ETH
        if (!swapParams.zeroForOne) return (this.afterSwap.selector, 0);

        // Mint points equal to 20% of the amount of ETH they spent
        // Since it's a zeroForOne swap:
        // if amountSpecified < 0:
        //      this is an "exact input for output" swap
        //      amount of ETH they spent is equal to |amountSpecified|
        // if amountSpecified > 0:
        //      this is an "exact output for input" swap
        //      amount of ETH they spent is equal to BalanceDelta.amount0()
        uint256 ethSpendAmount = uint256(int256(-delta.amount0()));
        uint256 pointsForSwap = ethSpendAmount / 5;

        // Mint the points
        _assignPoints(key.toId(), hookData, pointsForSwap);

        return (this.afterSwap.selector, 0);
    }
}
