// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @notice One per game, deployed at publish, immutable forever. Splits a
/// game's revenue between its developers and the platform, in basis points
/// fixed at construction. No function here can change a split, pause a
/// claim, or move anyone's money but their own — that absence is the whole
/// point: "splits are immutable once published" is a sentence a contract can
/// prove, not a policy this app promises to honour.
///
/// Payment doesn't call any accounting function here — a buyer's EIP-3009
/// authorization (or a plain value transfer) just credits this contract's
/// balance, the same way sending to any address does. There is still no
/// deposit bookkeeping; `totalReceived()` is derived from the chain's own
/// balance, which is correct regardless of how the money arrived and cannot
/// be made to disagree with it. (The contract does need a bare `receive()`
/// to accept that balance at all — see the one below; a contract with
/// neither `receive()` nor a payable `fallback()` rejects a plain value
/// transfer outright, confirmed directly when an early deploy without one
/// reverted on a real send during testing.)
///
/// Payouts are pull, not push, on purpose. Arc's blocklist reverts a value
/// transfer to or from a blocklisted address at the protocol level — a single
/// push transaction fanning out to every recipient at once would let one
/// blocklisted payee revert the whole distribution. Claiming isolates that:
/// one call moves one payee's share, so one frozen address costs that address
/// its claim and nobody else's.
///
/// But a pull-only `claim()` has a deadlock, and on Arc it is the normal case
/// rather than an edge one. Gas here is USDC, so paying for a transaction
/// means already holding USDC — and a developer whose first earnings are
/// sitting in this vault holds nothing. Their money is one transaction away
/// and they cannot afford the transaction. `claimFor` is the way out: anyone
/// may trigger a payee's claim, and the money still goes to the payee and
/// nowhere else. The platform spends a fraction of a cent of gas to unstick
/// someone, with no ability to redirect, withhold, or take a cut for doing it,
/// and no standing permission over the vault — and because it is open to
/// anyone, we are not a gatekeeper either. (The alternative was an ERC-4337
/// bundler and paymaster, or EIP-7702 delegation: a great deal of machinery to
/// avoid one `address` parameter.)
contract SplitVault {
    error ZeroAddress();
    error LengthMismatch();
    error DuplicateRecipient();
    error BpsOverflow();
    error BpsMismatch();
    error NothingOwed();
    error TransferFailed();

    uint256 private constant TOTAL_BPS = 10_000;

    /// @dev Every payee, platform included — see `bpsOf`. Exists for
    /// enumeration (`payees.length`, iterating off-chain); the mapping is
    /// what `claim()` actually reads.
    address[] public payees;
    mapping(address => uint16) public bpsOf;
    mapping(address => uint256) public claimed;

    /// The payee with the largest share, decided once at construction.
    /// Integer division floors every other payee's `owed()`; this one's is
    /// `totalReceived() minus everyone else's`, so whatever division left
    /// over lands with the biggest stake rather than being stranded in the
    /// contract forever. The old Hedera version of this exact system did the
    /// same thing for the same reason — see `fulfil.ts`'s `distributeSplits`.
    address public immutable remainderPayee;

    event Claimed(address indexed payee, uint256 amount);

    /// @param recipients Studio-side payees — developers, collaborators.
    /// @param bps Each recipient's share, basis points, same order as `recipients`.
    /// @param platform The platform's own payout address.
    /// @param platformBps The platform's share. `sum(bps) + platformBps` must equal 10,000 exactly.
    constructor(address[] memory recipients, uint16[] memory bps, address platform, uint16 platformBps) {
        if (recipients.length != bps.length) revert LengthMismatch();
        if (platform == address(0)) revert ZeroAddress();

        uint256 total = platformBps;
        _addPayee(platform, platformBps);
        address largest = platform;
        uint16 largestBps = platformBps;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            if (recipient == address(0)) revert ZeroAddress();
            if (recipient == platform || bpsOf[recipient] != 0) revert DuplicateRecipient();
            total += bps[i];
            _addPayee(recipient, bps[i]);
            if (bps[i] > largestBps) {
                largest = recipient;
                largestBps = bps[i];
            }
        }

        if (total != TOTAL_BPS) revert BpsMismatch();
        remainderPayee = largest;
    }

    /// Accepts a plain value transfer with no logic — required for the
    /// contract to receive money at all, see the note above `contract
    /// SplitVault`. Deliberately empty: there is nothing to record, since
    /// `totalReceived()` reads the balance directly rather than a counter
    /// this would have to keep in sync.
    receive() external payable {}

    function _addPayee(address payee, uint16 share) private {
        if (share == 0 || share > TOTAL_BPS) revert BpsOverflow();
        payees.push(payee);
        bpsOf[payee] = share;
    }

    function payeeCount() external view returns (uint256) {
        return payees.length;
    }

    /// Every unit of value this vault has ever held, received or paid out —
    /// the current balance plus everything already claimed. Basis points are
    /// applied to this, not to the live balance, so a payee's entitlement
    /// never shrinks just because someone else claimed first.
    function totalReceived() public view returns (uint256) {
        return address(this).balance + _totalClaimed();
    }

    function _totalClaimed() private view returns (uint256 sum) {
        for (uint256 i = 0; i < payees.length; i++) {
            sum += claimed[payees[i]];
        }
    }

    /// Every other payee's share floors to the nearest whole unit — Solidity
    /// integer division has no other option — which can strand up to
    /// `payees.length - 1` units with nobody entitled to them. Giving
    /// `remainderPayee` "whatever's left" instead of its own proportional
    /// floor means the sum of every `owed()` always equals `totalReceived()`
    /// exactly, for any amount received. Nothing is ever stuck.
    function owed(address payee) public view returns (uint256) {
        uint256 total = totalReceived();
        if (payee == remainderPayee) {
            uint256 othersOwed;
            for (uint256 i = 0; i < payees.length; i++) {
                if (payees[i] != remainderPayee) {
                    othersOwed += (total * bpsOf[payees[i]]) / TOTAL_BPS;
                }
            }
            return total - othersOwed;
        }
        return (total * bpsOf[payee]) / TOTAL_BPS;
    }

    function claimable(address payee) public view returns (uint256) {
        return owed(payee) - claimed[payee];
    }

    function claim() external {
        _claim(msg.sender);
    }

    /// Pay `payee` what they are owed, paid for by whoever calls this.
    ///
    /// Deliberately open to anyone, because the money can only ever go to
    /// `payee` — see the note above `contract SplitVault` for why this exists
    /// at all. The caller spends gas and gains nothing, so there is nothing
    /// here to abuse beyond wasting one's own money; the worst a caller can do
    /// is pay to deliver someone else's funds slightly earlier than they
    /// asked.
    function claimFor(address payee) external {
        if (payee == address(0)) revert ZeroAddress();
        _claim(payee);
    }

    /// Effects before the external call, deliberately — `claimed` is updated
    /// first so a reentrant call sees nothing left to claim, rather than
    /// relying on a guard.
    function _claim(address payee) private {
        uint256 amount = claimable(payee);
        if (amount == 0) revert NothingOwed();

        claimed[payee] += amount;

        (bool ok,) = payee.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Claimed(payee, amount);
    }
}
