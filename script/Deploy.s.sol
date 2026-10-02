// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {GameKey} from "../src/GameKey.sol";

/// Deploys GameRegistry and GameKey with the broadcaster as both operator and
/// minter — correct for this stage, where the same wallet stands in for the
/// backend's eventual operator address. A real deploy later just passes a
/// different address for each.
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        GameRegistry registry = new GameRegistry(deployer);
        GameKey key = new GameKey(deployer);

        vm.stopBroadcast();

        console.log("GameRegistry:", address(registry));
        console.log("GameKey:", address(key));
    }
}
