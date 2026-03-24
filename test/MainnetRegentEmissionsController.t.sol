// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    MainnetRegentEmissionsController,
    ISubjectRegistryMinimal
} from "src/revenue/MainnetRegentEmissionsController.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";
import {SimpleMintableERC20} from "src/SimpleMintableERC20.sol";

contract MainnetRegentEmissionsControllerTest is Test {
    uint256 internal constant EPOCH_LENGTH = 3 days;
    bytes32 internal constant SUBJECT_ID = keccak256("subject-1");
    bytes32 internal constant POOL_ID = keccak256("launch-pool");

    SimpleMintableERC20 internal regent;
    SimpleMintableERC20 internal usdc;
    SimpleMintableERC20 internal stakeToken;
    SubjectRegistry internal subjectRegistry;
    MainnetRegentEmissionsController internal controller;
    MockProtocolReserveSplitter internal splitter;
    MockLaunchFeeVaultRegent internal launchFeeVault;

    address internal treasurySafe = address(0xBEEF);
    address internal emissionRecipient = address(0xCAFE);
    address internal usdcTreasury = address(0xD00D);
    uint256 internal genesisTs = 1_000;

    function setUp() external {
        regent = new SimpleMintableERC20("Regent", "REGENT", 18, address(this), 0, address(this));
        usdc = new SimpleMintableERC20("USDC", "USDC", 6, address(this), 0, address(this));
        stakeToken = new SimpleMintableERC20("Stake", "STK", 18, address(this), 0, address(this));

        splitter = new MockProtocolReserveSplitter(address(usdc));
        launchFeeVault = new MockLaunchFeeVaultRegent(address(usdc));

        subjectRegistry = new SubjectRegistry(address(this));
        subjectRegistry.createSubject(
            SUBJECT_ID, address(stakeToken), address(splitter), treasurySafe, true, "Test Subject"
        );

        vm.prank(treasurySafe);
        subjectRegistry.setEmissionRecipient(SUBJECT_ID, 1, emissionRecipient);

        controller = new MainnetRegentEmissionsController(
            address(regent),
            address(usdc),
            ISubjectRegistryMinimal(address(subjectRegistry)),
            usdcTreasury,
            genesisTs,
            EPOCH_LENGTH,
            1,
            address(this)
        );

        regent.mint(address(this), 1_000_000 ether);
        usdc.mint(address(this), 1_000_000_000_000);
        regent.approve(address(controller), type(uint256).max);
        usdc.approve(address(controller), type(uint256).max);
    }

    function testCreditPublishAndClaimUsesSnapshottedRecipient() external {
        vm.warp(genesisTs + 1);

        uint32 epoch = controller.creditUsdc(
            SUBJECT_ID, 42_500_000, keccak256("credit-1"), bytes32("bridge"), keccak256("source")
        );
        assertEq(epoch, 1);
        assertEq(controller.subjectRevenueUsdc(1, SUBJECT_ID), 42_500_000);
        assertEq(controller.subjectRecipientSnapshot(1, SUBJECT_ID), emissionRecipient);

        vm.prank(treasurySafe);
        subjectRegistry.setEmissionRecipient(SUBJECT_ID, 1, address(0xABCD));

        vm.warp(genesisTs + EPOCH_LENGTH + 1);
        controller.publishEpochEmission(1, 1000 ether);

        uint256 claimable = controller.previewClaimable(1, SUBJECT_ID);
        assertEq(claimable, 1000 ether);

        controller.claim(1, SUBJECT_ID);
        assertEq(regent.balanceOf(emissionRecipient), 1000 ether);
        assertEq(regent.balanceOf(address(0xABCD)), 0);
    }

    function testPullSplitterAndLaunchVaultUsdcCreditsEpochRevenue() external {
        vm.warp(genesisTs + 1);

        usdc.mint(address(splitter), 12_000_000);
        usdc.mint(address(launchFeeVault), 8_000_000);

        (uint32 splitterEpoch, uint256 splitterReceived) =
            controller.pullSplitterUsdc(SUBJECT_ID, 12_000_000, keccak256("splitter"));
        assertEq(splitterEpoch, 1);
        assertEq(splitterReceived, 12_000_000);

        vm.prank(treasurySafe);
        controller.configureLaunchUsdcRoute(SUBJECT_ID, address(launchFeeVault), POOL_ID, true);

        (uint32 vaultEpoch, uint256 vaultReceived) =
            controller.pullLaunchVaultUsdc(SUBJECT_ID, 8_000_000, keccak256("vault"));
        assertEq(vaultEpoch, 1);
        assertEq(vaultReceived, 8_000_000);

        assertEq(controller.subjectRevenueUsdc(1, SUBJECT_ID), 20_000_000);
        assertEq(usdc.balanceOf(address(controller)), 20_000_000);
    }
}

contract MockProtocolReserveSplitter {
    address internal immutable usdc;

    constructor(address usdc_) {
        usdc = usdc_;
    }

    function withdrawProtocolReserve(address rewardToken, uint256 amount, address recipient) external {
        require(rewardToken == usdc, "TOKEN_MISMATCH");
        SimpleMintableERC20(usdc).transfer(recipient, amount);
    }
}

contract MockLaunchFeeVaultRegent {
    address internal immutable usdc;

    constructor(address usdc_) {
        usdc = usdc_;
    }

    function withdrawRegentShare(bytes32, address currency, uint256 amount, address recipient) external {
        require(currency == usdc, "TOKEN_MISMATCH");
        SimpleMintableERC20(usdc).transfer(recipient, amount);
    }
}
