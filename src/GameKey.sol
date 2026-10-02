// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Ownership of a purchased game. One collection for every game on
/// the platform; `gameOf[tokenId]` says which.
///
/// No admin function anywhere — no pause, no burn, no wipe, no freeze, and no
/// way to move a key except the owner's own `transferFrom`/`approve`, which
/// every ERC-721 grants its holder by definition. That absence is the
/// ownership claim itself: delisting a game cannot take a key back, and
/// neither can we. The one restriction that does exist — only `minter` may
/// mint — exists to stop forged keys, not to let anyone revoke a real one,
/// and `minter` is set once, at deployment, with no setter to ever change it.
contract GameKey is ERC721 {
    error NotMinter();
    error ZeroAddress();

    address public immutable minter;
    uint256 private _nextTokenId;

    mapping(uint256 => bytes32) public gameOf;

    constructor(address minter_) ERC721("Cosmic Game Sanctuary Key", "CGSKEY") {
        if (minter_ == address(0)) revert ZeroAddress();
        minter = minter_;
    }

    function mint(address to, bytes32 gameId) external returns (uint256 tokenId) {
        if (msg.sender != minter) revert NotMinter();
        tokenId = ++_nextTokenId;
        gameOf[tokenId] = gameId;
        _safeMint(to, tokenId);
    }
}
