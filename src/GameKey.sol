// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

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
///
/// Enumerable on purpose. "Does this wallet own game X" is asked on every
/// play, and the only other way to answer it is to scan `Transfer` logs —
/// which Arc's public RPC caps at just under 10,000 blocks (about 80 minutes)
/// per request. Enumerating a holder's keys is plain contract state, so it
/// works from any RPC at any age, and any third party can do the same check
/// without us.
contract GameKey is ERC721Enumerable {
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

    /// Everything `holder` owns and which game each key belongs to, in a
    /// single call. The same answer is available from the standard
    /// enumeration functions, but that takes a round trip per key and can
    /// straddle two blocks; one `eth_call` is one consistent snapshot.
    function keysOf(address holder) external view returns (uint256[] memory tokenIds, bytes32[] memory gameIds) {
        uint256 count = balanceOf(holder);
        tokenIds = new uint256[](count);
        gameIds = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 id = tokenOfOwnerByIndex(holder, i);
            tokenIds[i] = id;
            gameIds[i] = gameOf[id];
        }
    }

    /// The id of a key `holder` owns for `gameId`, or zero if they hold none.
    /// Zero is unambiguous: ids start at 1.
    function keyFor(address holder, bytes32 gameId) external view returns (uint256) {
        uint256 count = balanceOf(holder);
        for (uint256 i = 0; i < count; i++) {
            uint256 id = tokenOfOwnerByIndex(holder, i);
            if (gameOf[id] == gameId) return id;
        }
        return 0;
    }
}
