// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";

contract SubjectRegistryTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    address internal constant OWNER = address(0xA11CE);
    address internal constant STAKE_TOKEN = address(0xBEEF);
    address internal constant SPLITTER = address(0xC0FFEE);
    address internal constant NEXT_SPLITTER = address(0xC0FFED);
    address internal constant INITIAL_SAFE = address(0x1111);
    address internal constant NEXT_SAFE = address(0x2222);
    address internal constant SUBJECT_MANAGER = address(0x3333);

    SubjectRegistry internal registry;

    function setUp() external {
        registry = new SubjectRegistry(OWNER);

        vm.prank(OWNER);
        registry.createSubject(SUBJECT_ID, STAKE_TOKEN, SPLITTER, INITIAL_SAFE, true, "Atlas");
    }

    function testUpdateSubjectRotatesTreasurySafeAndManager() external {
        vm.prank(INITIAL_SAFE);
        registry.updateSubject(SUBJECT_ID, SPLITTER, NEXT_SAFE, true, "Atlas");

        SubjectRegistry.SubjectConfig memory subject = registry.getSubject(SUBJECT_ID);
        assertEq(subject.treasurySafe, NEXT_SAFE);
        assertEq(subject.splitter, SPLITTER);
        assertTrue(subject.active);

        assertFalse(registry.subjectManagers(SUBJECT_ID, INITIAL_SAFE));
        assertTrue(registry.subjectManagers(SUBJECT_ID, NEXT_SAFE));
        assertFalse(registry.canManageSubject(SUBJECT_ID, INITIAL_SAFE));
        assertTrue(registry.canManageSubject(SUBJECT_ID, NEXT_SAFE));
    }

    function testSubjectManagerCannotRedirectEconomicRoute() external {
        vm.prank(INITIAL_SAFE);
        registry.setSubjectManager(SUBJECT_ID, SUBJECT_MANAGER, true);

        vm.prank(SUBJECT_MANAGER);
        vm.expectRevert("ONLY_SUBJECT_CONTROLLER");
        registry.updateSubject(SUBJECT_ID, NEXT_SPLITTER, NEXT_SAFE, false, "Redirected");

        vm.prank(SUBJECT_MANAGER);
        vm.expectRevert("ONLY_SUBJECT_CONTROLLER");
        registry.setSubjectManager(SUBJECT_ID, address(0x4444), true);
    }

    function testSubjectManagerCanUpdateLabelAndClaimIdentity() external {
        vm.prank(INITIAL_SAFE);
        registry.setSubjectManager(SUBJECT_ID, SUBJECT_MANAGER, true);

        vm.prank(SUBJECT_MANAGER);
        registry.setSubjectLabel(SUBJECT_ID, "Atlas Prime");

        SubjectRegistry.SubjectConfig memory subject = registry.getSubject(SUBJECT_ID);
        assertEq(subject.label, "Atlas Prime");

        vm.prank(SUBJECT_MANAGER);
        bytes32 identityHash = registry.linkIdentity(SUBJECT_ID, 8453, address(0x5555), 7);

        assertEq(registry.subjectForIdentity(8453, address(0x5555), 7), SUBJECT_ID);
        assertTrue(identityHash != bytes32(0));
    }
}
