// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice The public listing log — what the wishlist agent actually reads.
///
/// This replaces the HCS listings topic the Hedera build used: the agent
/// watches these events via `eth_getLogs` instead of subscribing to a Mirror
/// Node topic, but the rule that made the pitch true on Hedera is unchanged
/// here — the agent learns about listings from this public,
/// independently-readable log, never from a database flag only we can see.
/// Anyone could build the same agent against this contract with no
/// permission from us, which is the whole point.
///
/// Everything that changes what is on offer goes through here, not just the
/// first listing: a price, a sale's deadline, a patch, a delisting and its
/// reversal. A price that only ever changed in our database is a price no
/// reader of this log can see, and `endsAt` is what lets a reader reason about
/// a sale's deadline instead of guessing.
///
/// `operator` is the one restriction, set once at deployment: only it may
/// write, because what's "real" still goes through moderation before it's
/// on-chain. That is a gate on who may log something, not an admin override
/// on anything already logged — there is no function here that edits or
/// removes a past event, and nothing here can touch `GameKey` or
/// `SplitVault`, so no call can revoke anyone's access or redirect any money.
contract GameRegistry {
    error NotOperator();
    error ZeroAddress();
    error AlreadyPublished();
    error NotPublished();
    error AlreadyDelisted();
    error NotDelisted();

    address public immutable operator;

    /// Zero means never published. Doubles as the publish guard and as a
    /// public way to look up a game's vault without replaying every event.
    mapping(bytes32 => address) public vaultOf;
    mapping(bytes32 => bool) public delisted;

    event Listed(bytes32 indexed gameId, string slug, uint256 priceUnits, address vault, string buildCid);
    /// `endsAt` is a unix timestamp, or zero when this isn't a timed sale.
    event PriceChanged(bytes32 indexed gameId, uint256 fromUnits, uint256 toUnits, uint64 endsAt);
    event BuildUpdated(bytes32 indexed gameId, uint32 version, string buildCid);
    event Delisted(bytes32 indexed gameId);
    event Relisted(bytes32 indexed gameId, uint256 priceUnits);
    /// How many people are waiting for a game, at the moment it crosses a
    /// threshold. Not price-bearing: this states interest, not an offer, so a
    /// reader watching for a price cannot mistake it for one.
    event Demand(bytes32 indexed gameId, uint32 wishlistCount, uint32 milestone);

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier published(bytes32 gameId) {
        if (vaultOf[gameId] == address(0)) revert NotPublished();
        _;
    }

    constructor(address operator_) {
        if (operator_ == address(0)) revert ZeroAddress();
        operator = operator_;
    }

    function publish(bytes32 gameId, string calldata slug, uint256 priceUnits, address vault, string calldata buildCid)
        external
        onlyOperator
    {
        if (vault == address(0)) revert ZeroAddress();
        if (vaultOf[gameId] != address(0)) revert AlreadyPublished();

        vaultOf[gameId] = vault;
        emit Listed(gameId, slug, priceUnits, vault, buildCid);
    }

    function setPrice(bytes32 gameId, uint256 fromUnits, uint256 toUnits, uint64 endsAt)
        external
        onlyOperator
        published(gameId)
    {
        emit PriceChanged(gameId, fromUnits, toUnits, endsAt);
    }

    function updateBuild(bytes32 gameId, uint32 version, string calldata buildCid)
        external
        onlyOperator
        published(gameId)
    {
        emit BuildUpdated(gameId, version, buildCid);
    }

    function delist(bytes32 gameId) external onlyOperator published(gameId) {
        if (delisted[gameId]) revert AlreadyDelisted();

        delisted[gameId] = true;
        emit Delisted(gameId);
    }

    /// Reverses a delisting a developer chose themselves. Moderation takedowns
    /// are kept apart from this off-chain; the contract only records the flag.
    function relist(bytes32 gameId, uint256 priceUnits) external onlyOperator published(gameId) {
        if (!delisted[gameId]) revert NotDelisted();

        delisted[gameId] = false;
        emit Relisted(gameId, priceUnits);
    }

    /// Publish how many people are waiting for a game.
    ///
    /// Here because it is the one thing a storefront normally keeps: knowing
    /// what people want before they buy it is the moat, so ours is a public
    /// count anyone can read — a developer deciding whether a discount is
    /// worth it included. Callers are expected to emit once per threshold
    /// crossed rather than once per wishlist save; the contract keeps no
    /// counter of its own, because the count it would keep could disagree with
    /// the one people actually see.
    function announceDemand(bytes32 gameId, uint32 wishlistCount, uint32 milestone)
        external
        onlyOperator
        published(gameId)
    {
        emit Demand(gameId, wishlistCount, milestone);
    }
}
