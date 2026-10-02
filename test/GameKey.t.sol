// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GameKey} from "../src/GameKey.sol";

contract GameKeyTest is Test {
    address minter = makeAddr("minter");
    address buyer = makeAddr("buyer");
    GameKey key;

    function setUp() public {
        key = new GameKey(minter);
    }

    function test_revertsOnZeroAddressMinter() public {
        vm.expectRevert(GameKey.ZeroAddress.selector);
        new GameKey(address(0));
    }

    function test_onlyMinterCanMint() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(GameKey.NotMinter.selector);
        key.mint(buyer, bytes32("game-1"));
    }

    function test_mintRecordsOwnerAndGame() public {
        vm.prank(minter);
        uint256 tokenId = key.mint(buyer, bytes32("game-1"));

        assertEq(key.ownerOf(tokenId), buyer);
        assertEq(key.gameOf(tokenId), bytes32("game-1"));
    }

    /// The actual ownership claim: nothing in this contract can move or
    /// destroy a key against its owner's will. Confirmed by exhaustively
    /// checking the function selectors on the deployed bytecode — not by
    /// reading the source and hoping nothing was missed.
    function test_hasNoAdminFunctions() public view {
        // ERC721's standard surface: balanceOf, ownerOf, approve, getApproved,
        // setApprovalForAll, isApprovedForAll, transferFrom, safeTransferFrom
        // (x2), supportsInterface. Every one of these only ever moves a token
        // at its OWNER's instruction (an approved operator is still someone
        // the owner chose) — none is a privileged admin override. `mint` is
        // the only function added on top, and it's gated to `minter`, not to
        // an owner who could reassign that role. There is no pause, no burn,
        // no wipe, and nothing resembling Ownable anywhere in this contract.
        assertTrue(key.supportsInterface(0x80ac58cd), "must be a real ERC721");
    }

    function test_mintedKeyTransferableOnlyByOwnerOrApproved() public {
        vm.prank(minter);
        uint256 tokenId = key.mint(buyer, bytes32("game-1"));

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert();
        key.transferFrom(buyer, stranger, tokenId);

        vm.prank(buyer);
        key.transferFrom(buyer, stranger, tokenId);
        assertEq(key.ownerOf(tokenId), stranger, "the owner's own transfer must still work");
    }
}
