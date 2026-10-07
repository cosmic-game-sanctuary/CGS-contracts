// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SplitVault} from "./SplitVault.sol";

/// @notice Deploys one `SplitVault` per game, exactly once.
///
/// Publishing a game is two on-chain steps — deploy the vault, then record the
/// listing on `GameRegistry` — and the second can fail while the first has
/// already happened. Without somewhere to look up "does this game already have
/// a vault", a retry would deploy a second one and list *that*, stranding the
/// first and quietly breaking the promise that a game's split is fixed at
/// publish. `vaultOf` makes the pair safe to retry: the deploy is idempotent,
/// so a publish can be repeated until it completes without ever producing a
/// second vault or a second split.
///
/// Deliberately not CREATE2. The plan called for it so a vault's address could
/// be computed before deployment, but the only thing that was for is this
/// idempotency, and a mapping does it in a fraction of the code — a salt and
/// an init-code hash would also have to be derived identically off-chain,
/// which is one more thing to get subtly wrong for no gain.
///
/// Unpermissioned on purpose. Anyone may deploy a vault for any `gameId`, and
/// that is harmless: a vault nobody lists receives nothing, and `GameRegistry`
/// — which *is* permissioned — decides which vault a game actually pays into.
/// Keeping the operator restriction in one place rather than two means there
/// is one answer to "who can change what's on offer", and it is the registry.
contract VaultFactory {
    error AlreadyDeployed();

    /// Zero until a game has a vault. The whole point of the contract.
    mapping(bytes32 => address) public vaultOf;

    event VaultDeployed(bytes32 indexed gameId, address vault, address[] payees, uint16[] bps);

    /// Deploy the vault for `gameId`, or return the one it already has.
    ///
    /// Returning rather than reverting on a repeat is what makes a half-failed
    /// publish recoverable: the caller gets the same address it would have got
    /// the first time and can carry on to the registry. Arguments are ignored
    /// on a repeat, by design — the split is fixed by whichever call deployed
    /// it, and a later caller passing a different one cannot change that.
    function deploy(
        bytes32 gameId,
        address[] calldata recipients,
        uint16[] calldata bps,
        address platform,
        uint16 platformBps
    ) external returns (address vault) {
        address existing = vaultOf[gameId];
        if (existing != address(0)) return existing;

        vault = address(new SplitVault(recipients, bps, platform, platformBps));
        vaultOf[gameId] = vault;

        SplitVault deployed = SplitVault(payable(vault));
        uint256 count = deployed.payeeCount();
        address[] memory payees = new address[](count);
        uint16[] memory shares = new uint16[](count);
        for (uint256 i = 0; i < count; i++) {
            payees[i] = deployed.payees(i);
            shares[i] = deployed.bpsOf(payees[i]);
        }

        // Emitted from the contract's own state rather than from the
        // arguments, so the log says what the vault will actually pay — the
        // platform payee included, which the arguments list separately.
        emit VaultDeployed(gameId, vault, payees, shares);
    }
}
