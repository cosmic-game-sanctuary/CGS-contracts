// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SplitVault} from "../src/SplitVault.sol";

/// One SplitVault shaped like a real studio's — one developer, one platform
/// cut at 5% — deployed on its own so there's a representative, verifiable
/// instance on the explorer distinct from the throwaway multi-recipient one
/// the live integration test script creates and drains.
contract DeployVault is Script {
    function run() external {
        vm.startBroadcast();
        address deployer = msg.sender;

        // A throwaway address standing in for a studio's payout address —
        // platform and recipient can't be the same address (the constructor
        // rejects it as a duplicate payee), and in the real product they
        // never would be either.
        address studio = 0xe50540E8D835017f0E394018Ff8D4E18dD507142;

        address[] memory recipients = new address[](1);
        recipients[0] = studio;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;
        SplitVault vault = new SplitVault(recipients, bps, deployer, 500);

        vm.stopBroadcast();
        console.log("SplitVault:", address(vault));
    }
}
