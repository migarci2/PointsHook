// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/libraries/Hooks.sol";

/**
 * @title HookMiner
 * @notice Mines a salt for CREATE2 such that the hook address matches the desired permissions.
 *         Strategy: iterate salts until (uint160(addr) & Hooks.ALL_HOOK_MASK) == expectedFlags.
 */
library HookMiner {
    /// @dev CREATE2 address = keccak256(0xff ++ deployer ++ salt ++ initCodeHash)[12:]
    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer)
        private
        pure
        returns (address)
    {
        bytes32 h = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(h)));
    }

    /// @dev Converts Permissions to bitmask according to Hooks.
    function permissionsToFlags(Hooks.Permissions memory p) internal pure returns (uint160 flags) {
        if (p.beforeInitialize)                flags |= Hooks.BEFORE_INITIALIZE_FLAG;
        if (p.afterInitialize)                 flags |= Hooks.AFTER_INITIALIZE_FLAG;
        if (p.beforeAddLiquidity)              flags |= Hooks.BEFORE_ADD_LIQUIDITY_FLAG;
        if (p.afterAddLiquidity)               flags |= Hooks.AFTER_ADD_LIQUIDITY_FLAG;
        if (p.beforeRemoveLiquidity)           flags |= Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG;
        if (p.afterRemoveLiquidity)            flags |= Hooks.AFTER_REMOVE_LIQUIDITY_FLAG;
        if (p.beforeSwap)                      flags |= Hooks.BEFORE_SWAP_FLAG;
        if (p.afterSwap)                       flags |= Hooks.AFTER_SWAP_FLAG;
        if (p.beforeDonate)                    flags |= Hooks.BEFORE_DONATE_FLAG;
        if (p.afterDonate)                     flags |= Hooks.AFTER_DONATE_FLAG;
        if (p.beforeSwapReturnDelta)           flags |= Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG;
        if (p.afterSwapReturnDelta)            flags |= Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
        if (p.afterAddLiquidityReturnDelta)    flags |= Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG;
        if (p.afterRemoveLiquidityReturnDelta) flags |= Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG;
    }

    /**
     * @param initCodeHash keccak256(initcode) of the hook (creationCode + constructor args)
     * @param deployer     address that will perform the CREATE2
     * @param desired      desired permissions
     * @param maxIters     iteration limit (0 = no limit)
     * @param seed         initial search offset
     */
    function mine(
        bytes32 initCodeHash,
        address deployer,
        Hooks.Permissions memory desired,
        uint256 maxIters,
        uint256 seed
    ) internal pure returns (bytes32 salt, address predicted) {
        uint160 want = permissionsToFlags(desired);
        require(want != 0, "HookMiner: no flags set");

        unchecked {
            for (uint256 i = seed; maxIters == 0 || i < seed + maxIters; ++i) {
                bytes32 s = bytes32(i);
                address addr = _computeCreate2Address(s, initCodeHash, deployer);
                if ((uint160(uint160(addr)) & Hooks.ALL_HOOK_MASK) == want) {
                    return (s, addr);
                }
            }
        }
        revert("HookMiner: not found within maxIters");
    }
}
