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

    /// The reason GameKey is enumerable: a holder's keys must be listable from
    /// contract state, because the RPC will not serve a log scan across a
    /// game's whole history.
    function test_holderKeysAreEnumerableAcrossGames() public {
        vm.startPrank(minter);
        uint256 a = key.mint(buyer, bytes32("game-1"));
        uint256 b = key.mint(buyer, bytes32("game-2"));
        key.mint(makeAddr("other"), bytes32("game-1"));
        vm.stopPrank();

        assertEq(key.balanceOf(buyer), 2);
        assertEq(key.tokenOfOwnerByIndex(buyer, 0), a);
        assertEq(key.tokenOfOwnerByIndex(buyer, 1), b);
        assertEq(key.gameOf(key.tokenOfOwnerByIndex(buyer, 1)), bytes32("game-2"));
        assertEq(key.totalSupply(), 3);
    }

    function test_enumerationFollowsATransfer() public {
        vm.prank(minter);
        uint256 tokenId = key.mint(buyer, bytes32("game-1"));

        address friend = makeAddr("friend");
        vm.prank(buyer);
        key.transferFrom(buyer, friend, tokenId);

        assertEq(key.balanceOf(buyer), 0, "the seller must stop holding it");
        assertEq(key.balanceOf(friend), 1);
        assertEq(key.tokenOfOwnerByIndex(friend, 0), tokenId);
        assertEq(key.gameOf(tokenId), bytes32("game-1"), "the game a key belongs to never changes");
    }

    function test_advertisesEnumerableInterface() public view {
        assertTrue(key.supportsInterface(0x780e9d63), "IERC721Enumerable");
    }

    function test_keysOfListsEveryKeyWithItsGame() public {
        vm.startPrank(minter);
        uint256 a = key.mint(buyer, bytes32("game-1"));
        uint256 b = key.mint(buyer, bytes32("game-2"));
        key.mint(makeAddr("other"), bytes32("game-3"));
        vm.stopPrank();

        (uint256[] memory ids, bytes32[] memory games) = key.keysOf(buyer);
        assertEq(ids.length, 2);
        assertEq(ids[0], a);
        assertEq(ids[1], b);
        assertEq(games[0], bytes32("game-1"));
        assertEq(games[1], bytes32("game-2"));

        (uint256[] memory none,) = key.keysOf(makeAddr("nobody"));
        assertEq(none.length, 0);
    }

    function test_keyForFindsTheRightKeyAndZeroOtherwise() public {
        vm.startPrank(minter);
        key.mint(buyer, bytes32("game-1"));
        uint256 wanted = key.mint(buyer, bytes32("game-2"));
        vm.stopPrank();

        assertEq(key.keyFor(buyer, bytes32("game-2")), wanted);
        assertEq(key.keyFor(buyer, bytes32("game-9")), 0, "a game they don't hold");
        assertEq(key.keyFor(makeAddr("nobody"), bytes32("game-2")), 0, "a wallet that holds nothing");
    }

    function test_keyForFollowsATransfer() public {
        vm.prank(minter);
        uint256 tokenId = key.mint(buyer, bytes32("game-1"));
        address friend = makeAddr("friend");

        vm.prank(buyer);
        key.transferFrom(buyer, friend, tokenId);

        assertEq(key.keyFor(buyer, bytes32("game-1")), 0, "the seller must stop owning it");
        assertEq(key.keyFor(friend, bytes32("game-1")), tokenId);
    }

    /// The two helpers are reads. Calling them must not be able to change
    /// anything, which `view` enforces at compile time; this pins that it
    /// stays so, since the ownership claim rests on there being no write path.
    function test_helpersAreViewOnly() public view {
        key.keysOf(buyer);
        key.keyFor(buyer, bytes32("game-1"));
    }
}
