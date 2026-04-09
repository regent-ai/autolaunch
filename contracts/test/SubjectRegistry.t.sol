// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";

contract SubjectRegistryTest is Test {
    bytes32 internal constant SUBJECT_ID = keccak256("subject");
    address internal constant OWNER = address(0xA11CE);
    address internal constant STAKE_TOKEN = address(0xBEEF);
    address internal constant SPLITTER = address(0xC0FFEE);
    address internal constant INITIAL_SAFE = address(0x1111);
    address internal constant NEXT_SAFE = address(0x2222);

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
}
