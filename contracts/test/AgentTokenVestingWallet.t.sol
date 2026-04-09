// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AgentTokenVestingWallet} from "src/AgentTokenVestingWallet.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract AgentTokenVestingWalletTest is Test {
    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant NEXT_BENEFICIARY = address(0xCAFE);
    uint64 internal constant START = 1_700_000_000;
    uint64 internal constant DURATION = 365 days;
    uint64 internal constant ROTATION_DELAY = 3 days;

    MintableERC20Mock internal token;
    MintableERC20Mock internal other;
    AgentTokenVestingWallet internal vestingWallet;

    function setUp() external {
        token = new MintableERC20Mock("Launch Token", "LT");
        other = new MintableERC20Mock("Other", "OTHER");
        vestingWallet = new AgentTokenVestingWallet(BENEFICIARY, START, DURATION, address(token));
        token.mint(address(vestingWallet), 1000e18);
    }

    function testReleaseTransfersOnlyVestedAmount() external {
        vm.warp(START + DURATION / 2);

        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 500e18);
        assertEq(vestingWallet.releasedLaunchToken(), 500e18);
    }

    function testProposeBeneficiaryRotation() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        assertEq(vestingWallet.pendingBeneficiary(), NEXT_BENEFICIARY);
        assertEq(vestingWallet.pendingBeneficiaryEta(), START + ROTATION_DELAY);
    }

    function testCancelBeneficiaryRotation() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.prank(BENEFICIARY);
        vestingWallet.cancelBeneficiaryRotation();

        assertEq(vestingWallet.pendingBeneficiary(), address(0));
        assertEq(vestingWallet.pendingBeneficiaryEta(), 0);
    }

    function testExecuteBeneficiaryRotationAfterDelay() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + ROTATION_DELAY);
        vestingWallet.executeBeneficiaryRotation();

        assertEq(vestingWallet.beneficiary(), NEXT_BENEFICIARY);
        assertEq(vestingWallet.pendingBeneficiary(), address(0));
        assertEq(vestingWallet.pendingBeneficiaryEta(), 0);
    }

    function testReleaseUsesOldBeneficiaryBeforeRotationExecutes() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + DURATION / 2);
        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 500e18);
        assertEq(token.balanceOf(NEXT_BENEFICIARY), 0);
    }

    function testReleaseUsesNewBeneficiaryAfterRotationExecutes() external {
        vm.warp(START);
        vm.prank(BENEFICIARY);
        vestingWallet.proposeBeneficiaryRotation(NEXT_BENEFICIARY);

        vm.warp(START + ROTATION_DELAY);
        vestingWallet.executeBeneficiaryRotation();

        vm.warp(START + DURATION / 2);
        uint256 released = vestingWallet.releaseLaunchToken();

        assertEq(released, 500e18);
        assertEq(token.balanceOf(BENEFICIARY), 0);
        assertEq(token.balanceOf(NEXT_BENEFICIARY), 500e18);
    }

    function testReleaseRevertsWhenNothingIsVested() external {
        vm.warp(START);

        vm.expectRevert("NOTHING_TO_RELEASE");
        vestingWallet.releaseLaunchToken();
    }

    function testBeneficiaryCanRescueUnsupportedTokenAndNative() external {
        other.mint(address(vestingWallet), 25e18);
        vm.deal(address(vestingWallet), 1 ether);

        vm.startPrank(BENEFICIARY);
        vestingWallet.rescueUnsupportedToken(address(other), 25e18, address(0x1234));
        vestingWallet.rescueNative(address(0x5678));
        vm.stopPrank();

        assertEq(other.balanceOf(address(0x1234)), 25e18);
        assertEq(address(vestingWallet).balance, 0);
        assertEq(address(0x5678).balance, 1 ether);
    }

    function testRescueBlocksLaunchToken() external {
        vm.prank(BENEFICIARY);
        vm.expectRevert("PROTECTED_TOKEN");
        vestingWallet.rescueUnsupportedToken(address(token), 1, BENEFICIARY);
    }
}
