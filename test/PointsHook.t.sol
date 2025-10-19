// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId} from "v4-core/types/PoolId.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {ERC1155TokenReceiver} from "solmate/src/tokens/ERC1155.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers, ERC1155TokenReceiver {
    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    PointsHook hook;

    uint256 poolIdUint;

    function setUp() public {
        // Manager + Routers
        deployFreshManagerAndRouters();

        // Token
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);

        // Hook at address with AFTER_SWAP flag
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(manager), address(flags));
        hook = PointsHook(address(flags));

        // Approvals
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Pool (ETH, TOKEN) with hook
        (key, ) = initPool(ethCurrency, tokenCurrency, hook, 3000, SQRT_PRICE_1_1);

        // Provide liquidity (0.1 ETH) around +/- 60 ticks
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        poolIdUint = uint256(PoolId.unwrap(key.toId()));
    }

    // --- helpers ---

    function _hookData(address user) internal pure returns (bytes memory) {
        return abi.encode(user);
    }

    function _points(address user) internal view returns (uint256) {
        return hook.balanceOf(user, poolIdUint);
    }

    function _swapExactEthIn(uint256 ethIn, address user) internal {
        swapRouter.swap{value: ethIn}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            _hookData(user)
        );
    }

    // --- tests ---

    function test_underCap_singleSmallSwap_mintsExpectedPoints() public {
        uint256 beforePts = _points(address(this));
        _swapExactEthIn(0.001 ether, address(this));
        uint256 afterPts = _points(address(this));
        assertEq(afterPts - beforePts, 2 * 10 ** 14);
    }

    function test_reachCap_singleSwap_exactCap() public {
        uint256 beforePts = _points(address(this));
        _swapExactEthIn(0.05 ether, address(this));
        uint256 afterPts = _points(address(this));
        assertEq(afterPts - beforePts, hook.DAILY_CAP_POINTS());
    }

    function test_accumulateAndClip_toCap() public {
        uint256 beforePts = _points(address(this));

        _swapExactEthIn(0.03 ether, address(this));
        uint256 midPts = _points(address(this));
        assertEq(midPts - beforePts, 6e15);

        _swapExactEthIn(0.03 ether, address(this));
        uint256 afterPts = _points(address(this));
        assertEq(afterPts - midPts, 4e15);
        assertEq(afterPts - beforePts, hook.DAILY_CAP_POINTS());
    }

    function test_noMint_afterCapReached_sameDay() public {
        _swapExactEthIn(0.05 ether, address(this));
        uint256 ptsAtCap = _points(address(this));
        assertEq(ptsAtCap, hook.DAILY_CAP_POINTS());

        _swapExactEthIn(0.001 ether, address(this));
        uint256 ptsAfter = _points(address(this));
        assertEq(ptsAfter, ptsAtCap);
    }

    function test_capResets_nextDay() public {
        _swapExactEthIn(0.05 ether, address(this));
        assertEq(_points(address(this)), hook.DAILY_CAP_POINTS());

        vm.warp(block.timestamp + 1 days + 1);

        uint256 before = _points(address(this));
        _swapExactEthIn(0.001 ether, address(this));
        uint256 after_ = _points(address(this));
        assertEq(after_ - before, 2 * 10 ** 14);
    }
}
