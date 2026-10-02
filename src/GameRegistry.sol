// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice The public listing log — what the wishlist agent actually reads.
///
/// This replaces the HCS listings topic the Hedera build used: the agent
/// watches `Listed`/`Delisted` events via `eth_getLogs` instead of subscribing
/// to a Mirror Node topic, but the rule that made the pitch true on Hedera is
/// unchanged here — the agent learns about listings from this public,
/// independently-readable log, never from a database flag only we can see.
/// Anyone could build the same agent against this contract with no
/// permission from us, which is the whole point.
///
/// `operator` is the one restriction, set once at deployment: only it may
/// publish or delist, because what's "real" still goes through moderation
/// before it's on-chain. That's a gate on who may log something, not an
/// admin override on anything already logged — there's no function here that
/// edits or removes a past event, and delisting never touches `GameKey` or
/// `SplitVault`, so it can't revoke anyone's access either.
contract GameRegistry {
    error NotOperator();
    error ZeroAddress();
    error AlreadyPublished();
    error NotPublished();
    error AlreadyDelisted();

    address public immutable operator;

    /// Zero means never published. Doubles as the publish guard and as a
    /// public way to look up a game's vault without replaying every event.
    mapping(bytes32 => address) public vaultOf;
    mapping(bytes32 => bool) public delisted;

    event Listed(bytes32 indexed gameId, string slug, uint256 priceUnits, address vault, string buildCid);
    event Delisted(bytes32 indexed gameId);

    constructor(address operator_) {
        if (operator_ == address(0)) revert ZeroAddress();
        operator = operator_;
    }

    function publish(bytes32 gameId, string calldata slug, uint256 priceUnits, address vault, string calldata buildCid)
        external
    {
        if (msg.sender != operator) revert NotOperator();
        if (vault == address(0)) revert ZeroAddress();
        if (vaultOf[gameId] != address(0)) revert AlreadyPublished();

        vaultOf[gameId] = vault;
        emit Listed(gameId, slug, priceUnits, vault, buildCid);
    }

    function delist(bytes32 gameId) external {
        if (msg.sender != operator) revert NotOperator();
        if (vaultOf[gameId] == address(0)) revert NotPublished();
        if (delisted[gameId]) revert AlreadyDelisted();

        delisted[gameId] = true;
        emit Delisted(gameId);
    }
}
