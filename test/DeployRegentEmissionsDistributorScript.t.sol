// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    DeployRegentEmissionsDistributorScript
} from "scripts/DeployRegentEmissionsDistributor.s.sol";
import {RegentEmissionsDistributorV2} from "src/revenue/RegentEmissionsDistributorV2.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract DeployRegentEmissionsDistributorScriptTest is Test {
    DeployRegentEmissionsDistributorScript internal script;
    MintableERC20Mock internal regent;

    function setUp() external {
        script = new DeployRegentEmissionsDistributorScript();
        regent = new MintableERC20Mock("Regent", "REGENT");

        vm.setEnv("REGENT_TOKEN_ADDRESS", vm.toString(address(regent)));
        vm.setEnv("REGENT_EMISSIONS_OWNER", vm.toString(address(0xBEEF)));
        vm.setEnv("REVENUE_EPOCH_GENESIS_TS", "1700000000");
        vm.setEnv("REGENT_EMISSIONS_CHAIN_ID", "1");
    }

  function testDeployFromEnvCreatesDistributor() external {
        RegentEmissionsDistributorV2 distributor = script.deployFromEnv();

        assertEq(address(distributor.regent()), address(regent));
        assertEq(distributor.genesisTs(), 1_700_000_000);
        assertEq(distributor.owner(), address(0xBEEF));
        assertTrue(distributor.hasRole(distributor.EPOCH_PUBLISHER_ROLE(), address(0xBEEF)));
        assertTrue(distributor.hasRole(distributor.PAUSER_ROLE(), address(0xBEEF)));
    }
}
