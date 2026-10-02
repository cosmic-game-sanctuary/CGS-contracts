// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameRegistry} from "../src/GameRegistry.sol";

contract GameRegistryTest is Test {
    address operator = makeAddr("operator");
    address vault = makeAddr("vault");
    GameRegistry registry;

    function setUp() public {
        registry = new GameRegistry(operator);
    }

    function test_revertsOnZeroAddressOperator() public {
        vm.expectRevert(GameRegistry.ZeroAddress.selector);
        new GameRegistry(address(0));
    }

    function test_onlyOperatorCanPublish() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(GameRegistry.NotOperator.selector);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");
    }

    function test_publishEmitsListedAndRecordsVault() public {
        vm.expectEmit(true, false, false, true);
        emit GameRegistry.Listed(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");

        vm.prank(operator);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");

        assertEq(registry.vaultOf(bytes32("game-1")), vault);
    }

    function test_cannotPublishSameGameTwice() public {
        vm.startPrank(operator);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");

        vm.expectRevert(GameRegistry.AlreadyPublished.selector);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");
        vm.stopPrank();
    }

    function test_delistRequiresPublishedFirst() public {
        vm.prank(operator);
        vm.expectRevert(GameRegistry.NotPublished.selector);
        registry.delist(bytes32("never-published"));
    }

    /// The product rule this contract has to uphold: delisting is a flag on
    /// the public log, never a revocation. It must not be able to touch
    /// `vaultOf`, and there is deliberately no code path here that could.
    function test_delistDoesNotTouchVault() public {
        vm.startPrank(operator);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");
        registry.delist(bytes32("game-1"));
        vm.stopPrank();

        assertEq(registry.vaultOf(bytes32("game-1")), vault, "delisting must not clear the vault");
        assertTrue(registry.delisted(bytes32("game-1")));
    }

    function test_cannotDelistTwice() public {
        vm.startPrank(operator);
        registry.publish(bytes32("game-1"), "a-game", 300_000, vault, "bafy...");
        registry.delist(bytes32("game-1"));

        vm.expectRevert(GameRegistry.AlreadyDelisted.selector);
        registry.delist(bytes32("game-1"));
        vm.stopPrank();
    }
}
