// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {RegentEmissionsDistributorV2} from "src/revenue/RegentEmissionsDistributorV2.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

contract RegentEmissionsDistributorV2Test is Test {
    MintableBurnableERC20Mock internal regent;
    RegentEmissionsDistributorV2 internal distributor;

    bytes32 internal constant SUBJECT_ID = keccak256("subject-42");
    address internal recipient = address(0xB453);

    function setUp() external {
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        distributor = new RegentEmissionsDistributorV2(address(regent), 1_000, address(this));

        regent.mint(address(this), 1_000e18);
        regent.approve(address(distributor), type(uint256).max);
    }

    function testPublishAndClaimEmission() external {
        vm.warp(1_000 + 3 days + 1);

        bytes32 leaf = keccak256(abi.encode(uint256(0), SUBJECT_ID, recipient, uint256(12.5e18)));
        distributor.publishEpochEmission(1, 100e18, 25e18, leaf, keccak256("manifest"));
        uint256 claimed = distributor.claim(1, 0, SUBJECT_ID, recipient, 12.5e18, new bytes32[](0));

        assertEq(claimed, 12.5e18);
        assertEq(regent.balanceOf(recipient), 12.5e18);
    }

    function testRejectsDuplicateClaimByIndex() external {
        vm.warp(1_000 + 3 days + 1);

        bytes32 leaf = keccak256(abi.encode(uint256(0), SUBJECT_ID, recipient, uint256(1e18)));
        distributor.publishEpochEmission(1, 10e18, 1e18, leaf, keccak256("manifest"));
        distributor.claim(1, 0, SUBJECT_ID, recipient, 1e18, new bytes32[](0));

        vm.expectRevert("ALREADY_CLAIMED");
        distributor.claim(1, 0, SUBJECT_ID, recipient, 1e18, new bytes32[](0));
    }

    function testRejectsDuplicateSubjectAcrossIndexes() external {
        vm.warp(1_000 + 3 days + 1);

        bytes32 leaf0 = keccak256(abi.encode(uint256(0), SUBJECT_ID, recipient, uint256(1e18)));
        bytes32 leaf1 = keccak256(abi.encode(uint256(1), SUBJECT_ID, recipient, uint256(2e18)));
        bytes32 root = leaf0 < leaf1
            ? keccak256(abi.encodePacked(leaf0, leaf1))
            : keccak256(abi.encodePacked(leaf1, leaf0));

        distributor.publishEpochEmission(1, 10e18, 3e18, root, keccak256("manifest"));

        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;

        distributor.claim(1, 0, SUBJECT_ID, recipient, 1e18, proof0);
        vm.expectRevert("SUBJECT_ALREADY_CLAIMED");
        distributor.claim(1, 1, SUBJECT_ID, recipient, 2e18, proof1);
    }
}
