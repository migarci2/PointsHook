// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PointsHook, PointsHookPerms} from "../src/PointsHook.sol";
import {HookMiner} from "./HookMiner.sol";

contract Create2Factory {
	event Deployed(address addr);
	function deploy(bytes32 salt, bytes memory initCode) external returns (address addr) {
		assembly {
			addr := create2(0, add(initCode, 0x20), mload(initCode), salt)
			if iszero(extcodesize(addr)) { revert(0, 0) }
		}
		emit Deployed(addr);
	}
}

interface ICreate2Factory {
	function deploy(bytes32 salt, bytes calldata initCode) external returns (address);
}

contract DeployHook is Script {
	function run() external {
		uint256 pk = vm.envUint("PRIVATE_KEY");
		address sender = vm.addr(pk);
		IPoolManager manager = IPoolManager(vm.envAddress("POOL_MANAGER"));

		uint256 nonce = vm.getNonce(sender);
		address factoryPredicted = vm.computeCreateAddress(sender, nonce);

		Hooks.Permissions memory perms = PointsHookPerms.permissions();

		bytes memory hookInitCode = abi.encodePacked(
			type(PointsHook).creationCode,
			abi.encode(manager)
		);
		bytes32 hookInitCodeHash = keccak256(hookInitCode);

		(bytes32 salt, address predictedHook) =
			HookMiner.mine(hookInitCodeHash, factoryPredicted, perms, 0, 0);

		console2.log("Sender (EOA):    ", sender);
		console2.log("Factory (pred.): ", factoryPredicted);
		console2.logBytes32(hookInitCodeHash);
		console2.logBytes32(salt);
		console2.log("Hook (pred.):    ", predictedHook);

		vm.startBroadcast(pk);

		if (factoryPredicted.code.length == 0) {
			new Create2Factory();
			require(factoryPredicted.code.length > 0, "factory not deployed");
		}

		address deployed = ICreate2Factory(factoryPredicted).deploy(salt, hookInitCode);
		vm.stopBroadcast();

		require(deployed == predictedHook, "deploy mismatch");
		console2.log("Hook deployed at:", deployed);
	}
}
