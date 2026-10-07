// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {SplitVault} from "../src/SplitVault.sol";

contract VaultFactoryTest is Test {
    VaultFactory factory;

    address platform = makeAddr("platform");
    address dev1 = makeAddr("dev1");
    address dev2 = makeAddr("dev2");

    bytes32 constant GAME = bytes32("game-1");
    bytes32 constant OTHER_GAME = bytes32("game-2");

    event VaultDeployed(bytes32 indexed gameId, address vault, address[] payees, uint16[] bps);

    function setUp() public {
        factory = new VaultFactory();
    }

    function _recipients() internal view returns (address[] memory r, uint16[] memory b) {
        r = new address[](2);
        r[0] = dev1;
        r[1] = dev2;
        b = new uint16[](2);
        b[0] = 7000;
        b[1] = 2500; // + 500 platform = 10000
    }

    function _deploy(bytes32 gameId) internal returns (address) {
        (address[] memory r, uint16[] memory b) = _recipients();
        return factory.deploy(gameId, r, b, platform, 500);
    }

    function test_deployRecordsTheVaultForTheGame() public {
        assertEq(factory.vaultOf(GAME), address(0), "no vault before publish");

        address vault = _deploy(GAME);

        assertTrue(vault != address(0));
        assertEq(factory.vaultOf(GAME), vault);
        assertEq(SplitVault(payable(vault)).bpsOf(dev1), 7000);
        assertEq(SplitVault(payable(vault)).bpsOf(platform), 500);
    }

    // The reason this contract exists: publishing is a deploy *and* a registry
    // write, and the second can fail after the first succeeded. A retry has to
    // converge on the same vault rather than make another one.
    function test_deployIsIdempotent() public {
        address first = _deploy(GAME);
        address second = _deploy(GAME);

        assertEq(second, first, "a retry returns the vault it already made");
    }

    function test_aRetryCannotRewriteTheSplit() public {
        address first = _deploy(GAME);

        // Someone calling again with a split that pays them everything must
        // not get a vault that honours it. The split is fixed by whichever
        // call deployed the vault, which is the product promise in contract
        // form.
        address[] memory greedy = new address[](1);
        greedy[0] = dev2;
        uint16[] memory bps = new uint16[](1);
        bps[0] = 9500;

        address again = factory.deploy(GAME, greedy, bps, platform, 500);

        assertEq(again, first);
        assertEq(SplitVault(payable(first)).bpsOf(dev1), 7000, "the original split stands");
        assertEq(SplitVault(payable(first)).bpsOf(dev2), 2500);
    }

    function test_differentGamesGetDifferentVaults() public {
        address a = _deploy(GAME);
        address b = _deploy(OTHER_GAME);

        assertTrue(a != b);
        assertEq(factory.vaultOf(OTHER_GAME), b);
    }

    function test_badSplitStillReverts() public {
        address[] memory r = new address[](1);
        r[0] = dev1;
        uint16[] memory b = new uint16[](1);
        b[0] = 9000; // + 500 != 10000

        vm.expectRevert(SplitVault.BpsMismatch.selector);
        factory.deploy(GAME, r, b, platform, 500);

        assertEq(factory.vaultOf(GAME), address(0), "a failed deploy records nothing");
    }

    // The log is what an outside reader uses to check a game's split without
    // trusting us, so it has to name the platform's cut too — which the
    // arguments pass separately and could otherwise omit.
    function test_eventReportsEveryPayeeIncludingThePlatform() public {
        (address[] memory r, uint16[] memory b) = _recipients();

        vm.recordLogs();
        address vault = factory.deploy(GAME, r, b, platform, 500);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != VaultDeployed.selector) continue;
            found = true;
            assertEq(logs[i].topics[1], GAME);
            (address loggedVault, address[] memory payees, uint16[] memory shares) =
                abi.decode(logs[i].data, (address, address[], uint16[]));
            assertEq(loggedVault, vault);
            assertEq(payees.length, 3, "two developers and the platform");
            assertEq(payees[0], platform, "the platform is payee zero");
            assertEq(shares[0], 500);
            uint256 total;
            for (uint256 j = 0; j < shares.length; j++) {
                total += shares[j];
            }
            assertEq(total, 10_000, "the logged shares add up to the whole");
        }
        assertTrue(found, "VaultDeployed was emitted");
    }

    // Anyone may deploy a vault for any id; it is GameRegistry that decides
    // which vault a game pays into. This records that the openness is deliberate
    // rather than an oversight.
    function test_anyoneCanDeploy() public {
        (address[] memory r, uint16[] memory b) = _recipients();

        vm.prank(makeAddr("stranger"));
        address vault = factory.deploy(GAME, r, b, platform, 500);

        assertEq(factory.vaultOf(GAME), vault);
    }

    function test_theVaultItMakesStillPaysOut() public {
        address vault = _deploy(GAME);
        vm.deal(vault, 10 ether);

        SplitVault(payable(vault)).claimFor(dev1);

        assertEq(dev1.balance, 7 ether);
        assertEq(SplitVault(payable(vault)).claimable(platform), 0.5 ether);
    }
}
