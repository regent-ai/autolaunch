// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AutolaunchLaunchToken} from "src/AutolaunchLaunchToken.sol";
import {AutolaunchTokenFactory} from "src/AutolaunchTokenFactory.sol";

contract AutolaunchTokenFactoryTest is Test {
    address internal constant RECIPIENT = address(0xA11CE);
    uint256 internal constant TOTAL_SUPPLY = 100_000_000_000e18;

    AutolaunchTokenFactory internal factory;

    function setUp() external {
        factory = new AutolaunchTokenFactory();
    }

    function testCreatesFixedSupplyLaunchToken() external {
        address tokenAddress = factory.createToken(
            "Regent Agent Token", "RAGENT", 18, TOTAL_SUPPLY, RECIPIENT, bytes(""), bytes32("salt")
        );

        AutolaunchLaunchToken token = AutolaunchLaunchToken(tokenAddress);
        assertEq(token.name(), "Regent Agent Token");
        assertEq(token.symbol(), "RAGENT");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(RECIPIENT), TOTAL_SUPPLY);
    }

    function testRejectsZeroRecipient() external {
        vm.expectRevert("RECIPIENT_ZERO");
        factory.createToken(
            "Regent Agent Token", "RAGENT", 18, TOTAL_SUPPLY, address(0), bytes(""), 0
        );
    }

    function testRejectsZeroSupply() external {
        vm.expectRevert("SUPPLY_ZERO");
        factory.createToken("Regent Agent Token", "RAGENT", 18, 0, RECIPIENT, bytes(""), 0);
    }

    function testRejectsEmptyName() external {
        vm.expectRevert("NAME_EMPTY");
        factory.createToken("", "RAGENT", 18, TOTAL_SUPPLY, RECIPIENT, bytes(""), 0);
    }

    function testRejectsEmptySymbol() external {
        vm.expectRevert("SYMBOL_EMPTY");
        factory.createToken("Regent Agent Token", "", 18, TOTAL_SUPPLY, RECIPIENT, bytes(""), 0);
    }

    function testRejectsNon18Decimals() external {
        vm.expectRevert("DECIMALS_MUST_BE_18");
        factory.createToken(
            "Regent Agent Token", "RAGENT", 6, TOTAL_SUPPLY, RECIPIENT, bytes(""), 0
        );
    }

    function testRejectsNonEmptyConfigData() external {
        vm.expectRevert("CONFIG_DATA_NONEMPTY");
        factory.createToken("Regent Agent Token", "RAGENT", 18, TOTAL_SUPPLY, RECIPIENT, hex"01", 0);
    }
}
