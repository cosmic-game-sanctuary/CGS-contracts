// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

/// The factory takes no constructor arguments and holds no privileged role —
/// anyone may deploy a vault through it, and `GameRegistry` is what decides
/// which vault a game pays into. See the notes on `VaultFactory`.
contract DeployFactory is Script {
    function run() external {
        vm.startBroadcast();
        VaultFactory factory = new VaultFactory();
        vm.stopBroadcast();

        console.log("VaultFactory:", address(factory));
    }
}
