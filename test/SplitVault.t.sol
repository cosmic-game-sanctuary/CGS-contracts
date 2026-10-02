// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SplitVault} from "../src/SplitVault.sol";

contract SplitVaultTest is Test {
    address platform = makeAddr("platform");
    address dev1 = makeAddr("dev1");
    address dev2 = makeAddr("dev2");
    address dev3 = makeAddr("dev3");

    // The well-known blocklisted address Arc Testnet seeds from the standard
    // test mnemonic, mnemonic index 1 — a value transfer to or from it
    // reverts at the protocol level. See docs.arc.io/arc/references/contract-addresses
    // "Test addresses for restricted transfer behavior".
    address constant BLOCKLISTED = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    function _deploy(address[] memory recipients, uint16[] memory bps, uint16 platformBps)
        internal
        returns (SplitVault)
    {
        return new SplitVault(recipients, bps, platform, platformBps);
    }

    function test_revertsOnBpsMismatch() public {
        address[] memory recipients = new address[](1);
        recipients[0] = dev1;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9000; // + 500 platform = 9500, not 10000

        vm.expectRevert(SplitVault.BpsMismatch.selector);
        _deploy(recipients, bps, 500);
    }

    function test_revertsOnZeroAddressRecipient() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        _deploy(recipients, bps, 500);
    }

    function test_revertsOnZeroAddressPlatform() public {
        address[] memory recipients = new address[](1);
        recipients[0] = dev1;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;

        vm.expectRevert(SplitVault.ZeroAddress.selector);
        new SplitVault(recipients, bps, address(0), 500);
    }

    function test_revertsOnDuplicateRecipient() public {
        address[] memory recipients = new address[](2);
        recipients[0] = dev1;
        recipients[1] = dev1;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 4750;
        bps[1] = 4750;

        vm.expectRevert(SplitVault.DuplicateRecipient.selector);
        _deploy(recipients, bps, 500);
    }

    function test_claimByNonRecipientReverts() public {
        SplitVault vault = _simpleVault();
        vm.deal(address(vault), 1 ether);

        vm.prank(makeAddr("stranger"));
        vm.expectRevert(SplitVault.NothingOwed.selector);
        vault.claim();
    }

    function test_claimTwicePaysOnlyOnce() public {
        SplitVault vault = _simpleVault();
        vm.deal(address(vault), 1 ether);

        vm.prank(dev1);
        vault.claim();
        uint256 balanceAfterFirst = dev1.balance;

        vm.prank(dev1);
        vm.expectRevert(SplitVault.NothingOwed.selector);
        vault.claim();

        assertEq(dev1.balance, balanceAfterFirst, "second claim must transfer nothing");
    }

    /// Arc's blocklist is enforced by the live network, not by the EVM
    /// bytecode `arc-forge test --network arc` runs locally — confirmed
    /// directly: a plain value transfer to BLOCKLISTED succeeds in this
    /// local run (the fallback call returns `Stop`, not a revert), because
    /// the local simulator has no concept of Arc's compliance layer. So this
    /// test checks only what's actually ours to guarantee: that one payee's
    /// status, whatever it is, never blocks another payee's claim from the
    /// same vault. The real blocklist enforcement — that BLOCKLISTED's own
    /// claim reverts — is verified separately on live Arc Testnet (see
    /// script/VerifyBlocklist.s.sol), which is the only environment where
    /// that rule actually exists.
    function test_onePayeeNeverBlocksAnother() public {
        address[] memory recipients = new address[](2);
        recipients[0] = BLOCKLISTED;
        recipients[1] = dev1;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 4750;
        bps[1] = 4750;
        SplitVault vault = _deploy(recipients, bps, 500);
        vm.deal(address(vault), 1 ether);

        vm.prank(dev1);
        vault.claim();
        assertGt(dev1.balance, 0, "a payee's claim must not depend on any other payee's status");

        vm.prank(platform);
        vault.claim();
        assertGt(platform.balance, 0, "the platform's claim must not depend on any other payee's status");
    }

    /// Three recipients at 3333/3333/3334 bps over an amount that doesn't
    /// divide evenly. Integer division floors every share but the largest;
    /// this proves the sum of every claim exhausts the vault exactly, with
    /// nothing left stranded in it.
    function test_roundingLeavesNothingStranded() public {
        address[] memory recipients = new address[](3);
        recipients[0] = dev1;
        recipients[1] = dev2;
        recipients[2] = dev3;
        uint16[] memory bps = new uint16[](3);
        bps[0] = 3333;
        bps[1] = 3333;
        bps[2] = 3333;
        // A zero share is refused by the constructor (BpsOverflow), so the
        // platform takes the last unit of the 10,000 rather than 0 — still an
        // odd total that doesn't divide evenly four ways, same proof either way.
        SplitVault vault = _deploy(recipients, bps, 1);

        uint256 amount = 1_000_003; // deliberately not divisible cleanly
        vm.deal(address(vault), amount);

        address[] memory claimants = new address[](4);
        claimants[0] = platform;
        claimants[1] = dev1;
        claimants[2] = dev2;
        claimants[3] = dev3;

        uint256 totalPaidOut;
        for (uint256 i = 0; i < claimants.length; i++) {
            uint256 before = claimants[i].balance;
            vm.prank(claimants[i]);
            vault.claim();
            totalPaidOut += claimants[i].balance - before;
        }

        assertEq(totalPaidOut, amount, "every wei must be claimed, none stranded");
        assertEq(address(vault).balance, 0, "the vault must be fully drained");
    }

    function test_totalReceivedAccountsForAlreadyClaimedFunds() public {
        SplitVault vault = _simpleVault();
        vm.deal(address(vault), 1 ether);

        vm.prank(dev1);
        vault.claim();

        // More money arrives after the first claim. A second claimant's
        // share must be computed against the running total (what's left plus
        // what's already gone out), not just the live balance.
        vm.deal(address(vault), address(vault).balance + 1 ether);

        assertEq(vault.totalReceived(), 2 ether, "totalReceived must include what's already claimed");
    }

    function _simpleVault() internal returns (SplitVault) {
        address[] memory recipients = new address[](1);
        recipients[0] = dev1;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;
        return _deploy(recipients, bps, 500);
    }

    // ─── claimFor: the gas deadlock ──────────────────────────────────────────
    //
    // On Arc gas is USDC, so a developer whose only money is in this vault
    // cannot afford the transaction that would release it. These cover the way
    // out, and that it cannot be turned into a way to take someone's money.

    function _oneDevVault() internal returns (SplitVault) {
        address[] memory recipients = new address[](1);
        recipients[0] = dev1;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;
        SplitVault vault = _deploy(recipients, bps, 500);
        vm.deal(address(vault), 10 ether);
        return vault;
    }

    function test_claimForPaysThePayeeNotTheCaller() public {
        SplitVault vault = _oneDevVault();
        address stranger = makeAddr("stranger");

        // The case that matters: the payee has nothing, so on Arc they could
        // not have sent this transaction themselves.
        vm.deal(dev1, 0);
        assertEq(dev1.balance, 0);

        uint256 strangerBefore = stranger.balance;
        vm.prank(stranger);
        vault.claimFor(dev1);

        assertEq(dev1.balance, 9.5 ether, "the payee got their share");
        assertEq(stranger.balance, strangerBefore, "the caller got nothing for it");
    }

    function test_claimForCannotRedirectToTheCaller() public {
        SplitVault vault = _oneDevVault();
        address thief = makeAddr("thief");

        // A non-payee has nothing owed, so there is no share to claim "for"
        // them — the only address claimFor can pay is one with a real share.
        vm.prank(thief);
        vm.expectRevert(SplitVault.NothingOwed.selector);
        vault.claimFor(thief);

        assertEq(thief.balance, 0);
    }

    function test_claimForCannotBeUsedTwice() public {
        SplitVault vault = _oneDevVault();

        vault.claimFor(dev1);
        assertEq(dev1.balance, 9.5 ether);

        // Repeated calls are the expected shape of this — anyone may call it,
        // so it will be called again. It must be worth nothing the second time.
        vm.expectRevert(SplitVault.NothingOwed.selector);
        vault.claimFor(dev1);
        assertEq(dev1.balance, 9.5 ether);
    }

    function test_claimForAndClaimShareTheSameLedger() public {
        SplitVault vault = _oneDevVault();

        vault.claimFor(dev1);
        // Having been paid by someone else's transaction must leave nothing
        // for the payee's own claim() to find, or the two paths together would
        // pay twice.
        vm.prank(dev1);
        vm.expectRevert(SplitVault.NothingOwed.selector);
        vault.claim();
    }

    function test_claimForRejectsZeroAddress() public {
        SplitVault vault = _oneDevVault();
        vm.expectRevert(SplitVault.ZeroAddress.selector);
        vault.claimFor(address(0));
    }

    function test_claimForOneBlocklistedPayeeDoesNotBlockTheOthers() public {
        address[] memory recipients = new address[](2);
        recipients[0] = dev1;
        recipients[1] = BLOCKLISTED;
        uint16[] memory bps = new uint16[](2);
        bps[0] = 5000;
        bps[1] = 4500;
        SplitVault vault = _deploy(recipients, bps, 500);
        vm.deal(address(vault), 10 ether);

        // The reason payouts are pull rather than push survives claimFor:
        // one call moves one payee's share, so a payee who cannot receive
        // costs only themselves. (Locally the transfer succeeds — the
        // blocklist is enforced by Arc, not by the EVM — so this asserts the
        // isolation property, which is what the design actually rests on.)
        vault.claimFor(dev1);
        assertEq(dev1.balance, 5 ether, "an unaffected payee is paid in full");
        assertEq(vault.claimable(dev1), 0);
        assertEq(vault.claimable(platform), 0.5 ether, "and everyone else's claim is untouched");
    }
}
