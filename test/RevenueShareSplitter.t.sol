// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RevenueShareSplitter} from "src/revenue/RevenueShareSplitter.sol";
import {RevenueIngressAccount} from "src/revenue/RevenueIngressAccount.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

contract RevenueShareSplitterTest is Test {
    uint256 internal constant XYZ = 1e18;
    uint256 internal constant USDC = 1e6;
    uint256 internal constant WETH = 1e18;

    MintableBurnableERC20Mock internal stakeToken;
    MintableBurnableERC20Mock internal usdc;
    MintableBurnableERC20Mock internal weth;
    RevenueShareSplitter internal splitter;
    RevenueIngressAccount internal ingress;

    address internal treasury = address(0xA11CE);
    address internal protocolTreasury = address(0xBEEF);
    address internal alice = address(0xA1);
    address internal bob = address(0xB2);
    address internal carol = address(0xC3);
    address internal dave = address(0xD4);
    address internal eve = address(0xE5);

    function setUp() external {
        stakeToken = new MintableBurnableERC20Mock("Agent", "XYZ", 18);
        usdc = new MintableBurnableERC20Mock("USD Coin", "USDC", 6);
        weth = new MintableBurnableERC20Mock("Wrapped Ether", "WETH", 18);

        splitter = new RevenueShareSplitter(
            address(stakeToken), treasury, protocolTreasury, 100, "XYZ splitter", address(this)
        );
        splitter.setAllowedRewardToken(address(usdc), true);
        splitter.setAllowedRewardToken(address(weth), true);
        splitter.setAllowedRewardToken(address(stakeToken), true);

        ingress = new RevenueIngressAccount(address(splitter), bytes32("xyz-ingress-1"), address(this));

        stakeToken.mint(alice, 200 * XYZ);
        stakeToken.mint(bob, 150 * XYZ);
        stakeToken.mint(carol, 50 * XYZ);
        stakeToken.mint(dave, 30 * XYZ);
        stakeToken.mint(eve, 20 * XYZ);
        stakeToken.mint(treasury, 550 * XYZ); // total supply = 1,000

        vm.startPrank(alice);
        stakeToken.approve(address(splitter), type(uint256).max);
        splitter.stake(200 * XYZ, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        stakeToken.approve(address(splitter), type(uint256).max);
        splitter.stake(100 * XYZ, bob);
        vm.stopPrank();

        vm.startPrank(carol);
        stakeToken.approve(address(splitter), type(uint256).max);
        splitter.stake(50 * XYZ, carol);
        vm.stopPrank();

        vm.startPrank(dave);
        stakeToken.approve(address(splitter), type(uint256).max);
        splitter.stake(30 * XYZ, dave);
        vm.stopPrank();

        vm.startPrank(eve);
        stakeToken.approve(address(splitter), type(uint256).max);
        splitter.stake(20 * XYZ, eve);
        vm.stopPrank();
    }

    function testMainScenarioAccounting() external {
        assertEq(splitter.totalStaked(), 400 * XYZ);

        usdc.mint(address(ingress), 10_000 * USDC);
        ingress.sweepToken(address(usdc), bytes32("invoice_usdc_1"));

        assertEq(splitter.protocolReserve(address(usdc)), 100 * USDC);
        assertEq(splitter.treasuryResidual(address(usdc)), 5_940 * USDC);
        assertEq(splitter.previewClaimable(alice, address(usdc)), 1_980 * USDC);
        assertEq(splitter.previewClaimable(bob, address(usdc)), 990 * USDC);
        assertEq(splitter.previewClaimable(carol, address(usdc)), 495 * USDC);
        assertEq(splitter.previewClaimable(dave, address(usdc)), 297 * USDC);
        assertEq(splitter.previewClaimable(eve, address(usdc)), 198 * USDC);

        vm.startPrank(bob);
        splitter.stake(50 * XYZ, bob);
        vm.stopPrank();
        assertEq(splitter.totalStaked(), 450 * XYZ);
        assertEq(splitter.previewClaimable(bob, address(usdc)), 990 * USDC);

        vm.prank(dave);
        splitter.unstake(10 * XYZ, dave);
        assertEq(splitter.totalStaked(), 440 * XYZ);
        assertEq(stakeToken.balanceOf(dave), 10 * XYZ);
        assertEq(splitter.previewClaimable(dave, address(usdc)), 297 * USDC);

        weth.mint(address(ingress), 1_000 * WETH);
        ingress.sweepToken(address(weth), bytes32("invoice_weth_1"));

        assertEq(splitter.protocolReserve(address(weth)), 10 * WETH);
        assertEq(splitter.treasuryResidual(address(weth)), 5544e17);
        assertEq(splitter.previewClaimable(alice, address(weth)), 198e18);
        assertEq(splitter.previewClaimable(bob, address(weth)), 1485e17);
        assertEq(splitter.previewClaimable(carol, address(weth)), 495e17);
        assertEq(splitter.previewClaimable(dave, address(weth)), 198e17);
        assertEq(splitter.previewClaimable(eve, address(weth)), 198e17);

        address[] memory usdcOnly = new address[](1);
        usdcOnly[0] = address(usdc);
        vm.prank(alice);
        splitter.claim(usdcOnly, alice);
        assertEq(usdc.balanceOf(alice), 1_980 * USDC);
        assertEq(splitter.previewClaimable(alice, address(usdc)), 0);
        assertEq(splitter.previewClaimable(alice, address(weth)), 198e18);

        vm.prank(carol);
        splitter.unstake(50 * XYZ, carol);
        assertEq(splitter.totalStaked(), 390 * XYZ);
        assertEq(stakeToken.balanceOf(carol), 50 * XYZ);
        assertEq(splitter.previewClaimable(carol, address(usdc)), 495 * USDC);
        assertEq(splitter.previewClaimable(carol, address(weth)), 495e17);

        usdc.mint(address(ingress), 5_000 * USDC);
        ingress.sweepToken(address(usdc), bytes32("invoice_usdc_2"));

        assertEq(splitter.protocolReserve(address(usdc)), 150 * USDC);
        assertEq(splitter.treasuryResidual(address(usdc)), 89595e5);
        assertEq(splitter.previewClaimable(alice, address(usdc)), 990 * USDC);
        assertEq(splitter.previewClaimable(bob, address(usdc)), 17325e5);
        assertEq(splitter.previewClaimable(carol, address(usdc)), 495 * USDC);
        assertEq(splitter.previewClaimable(dave, address(usdc)), 396 * USDC);
        assertEq(splitter.previewClaimable(eve, address(usdc)), 297 * USDC);

        address[] memory both = new address[](2);
        both[0] = address(usdc);
        both[1] = address(weth);
        vm.prank(bob);
        splitter.claimAllKnown(0, 10, 0, bob);
        assertEq(usdc.balanceOf(bob), 17325e5);
        assertEq(weth.balanceOf(bob), 1485e17);
        assertEq(splitter.previewClaimable(bob, address(usdc)), 0);
        assertEq(splitter.previewClaimable(bob, address(weth)), 0);
    }

    function testTreasuryStakingIsRevenueNeutral() external {
        MintableBurnableERC20Mock controlStake = new MintableBurnableERC20Mock("Neutral", "NEUT", 18);
        controlStake.mint(alice, 100 * XYZ);
        controlStake.mint(treasury, 900 * XYZ);

        RevenueShareSplitter control = new RevenueShareSplitter(
            address(controlStake), treasury, protocolTreasury, 100, "control", address(this)
        );
        control.setAllowedRewardToken(address(usdc), true);

        vm.startPrank(alice);
        controlStake.approve(address(control), type(uint256).max);
        control.stake(100 * XYZ, alice);
        vm.stopPrank();

        usdc.mint(address(this), 10_000 * USDC);
        usdc.approve(address(control), type(uint256).max);
        control.depositToken(address(usdc), 10_000 * USDC, bytes32("direct"), bytes32("1"));
        uint256 treasuryTakeNoStake = control.treasuryResidual(address(usdc));

        MintableBurnableERC20Mock stakedStake = new MintableBurnableERC20Mock("Neutral2", "NEUT2", 18);
        stakedStake.mint(alice, 100 * XYZ);
        stakedStake.mint(treasury, 900 * XYZ);

        RevenueShareSplitter stakedTreasury = new RevenueShareSplitter(
            address(stakedStake), treasury, protocolTreasury, 100, "stakedTreasury", address(this)
        );
        stakedTreasury.setAllowedRewardToken(address(usdc), true);

        vm.startPrank(alice);
        stakedStake.approve(address(stakedTreasury), type(uint256).max);
        stakedTreasury.stake(100 * XYZ, alice);
        vm.stopPrank();

        vm.startPrank(treasury);
        stakedStake.approve(address(stakedTreasury), type(uint256).max);
        stakedTreasury.stake(900 * XYZ, treasury);
        vm.stopPrank();

        usdc.mint(address(this), 10_000 * USDC);
        usdc.approve(address(stakedTreasury), type(uint256).max);
        stakedTreasury.depositToken(address(usdc), 10_000 * USDC, bytes32("direct"), bytes32("2"));

        uint256 treasuryResidualWithStake = stakedTreasury.treasuryResidual(address(usdc));
        uint256 treasuryAsStaker = stakedTreasury.previewClaimable(treasury, address(usdc));

        assertEq(treasuryTakeNoStake, 8_910 * USDC);
        assertEq(treasuryResidualWithStake + treasuryAsStaker, 8_910 * USDC);
    }

    function testBurnChangesFutureDepositsOnly() external {
        usdc.mint(address(this), 1_000 * USDC);
        usdc.approve(address(splitter), type(uint256).max);
        splitter.depositToken(address(usdc), 1_000 * USDC, bytes32("before_burn"), bytes32("1"));
        uint256 aliceBefore = splitter.previewClaimable(alice, address(usdc));

        stakeToken.burn(treasury, 100 * XYZ);
        assertEq(stakeToken.totalSupply(), 900 * XYZ);

        usdc.mint(address(this), 1_000 * USDC);
        usdc.approve(address(splitter), type(uint256).max);
        splitter.depositToken(address(usdc), 1_000 * USDC, bytes32("after_burn"), bytes32("2"));

        uint256 aliceAfter = splitter.previewClaimable(alice, address(usdc)) - aliceBefore;
        assertEq(aliceAfter, 220 * USDC);
    }

    function testUnsupportedRewardTokenDoesNotSweep() external {
        MintableBurnableERC20Mock junk = new MintableBurnableERC20Mock("Junk", "JUNK", 18);
        junk.mint(address(ingress), 1e18);
        vm.expectRevert("REWARD_TOKEN_NOT_ALLOWED");
        ingress.sweepToken(address(junk), bytes32("junk"));
    }

    function testStakeTokenCanAlsoBeRewardToken() external {
        stakeToken.mint(address(ingress), 100 * XYZ);
        ingress.sweepToken(address(stakeToken), bytes32("own_token_income"));
        assertGt(splitter.previewClaimable(alice, address(stakeToken)), 0);
        assertEq(splitter.stakedBalance(alice), 200 * XYZ);
    }

    function testSecondSweepOfSameBalanceCreditsZero() external {
        usdc.mint(address(ingress), 1_000 * USDC);
        ingress.sweepToken(address(usdc), bytes32("once"));

        uint256 reserveBefore = splitter.protocolReserve(address(usdc));
        uint256 residualBefore = splitter.treasuryResidual(address(usdc));

        vm.expectRevert("NOTHING_TO_SWEEP");
        ingress.sweepToken(address(usdc), bytes32("twice"));

        assertEq(splitter.protocolReserve(address(usdc)), reserveBefore);
        assertEq(splitter.treasuryResidual(address(usdc)), residualBefore);
    }
}
