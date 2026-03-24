// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    DeployMainnetRegentEmissionsControllerScript
} from "scripts/DeployMainnetRegentEmissionsController.s.sol";
import {MainnetRegentEmissionsController} from "src/revenue/MainnetRegentEmissionsController.sol";
import {SimpleMintableERC20} from "src/SimpleMintableERC20.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";

contract DeployMainnetRegentEmissionsControllerScriptTest is Test {
    DeployMainnetRegentEmissionsControllerScript internal script;
    SimpleMintableERC20 internal regent;
    SimpleMintableERC20 internal usdc;
    SubjectRegistry internal subjectRegistry;

    function setUp() external {
        script = new DeployMainnetRegentEmissionsControllerScript();
        regent = new SimpleMintableERC20("Regent", "REGENT", 18, address(this), 0, address(this));
        usdc = new SimpleMintableERC20("USDC", "USDC", 6, address(this), 0, address(this));
        subjectRegistry = new SubjectRegistry(address(this));

        vm.setEnv("REGENT_TOKEN_ADDRESS", vm.toString(address(regent)));
        vm.setEnv("ETH_MAINNET_USDC_ADDRESS", vm.toString(address(usdc)));
        vm.setEnv("SUBJECT_REGISTRY_ADDRESS", vm.toString(address(subjectRegistry)));
        vm.setEnv("REGENT_USDC_TREASURY", vm.toString(address(0xCAFE)));
        vm.setEnv("REGENT_EMISSIONS_OWNER", vm.toString(address(0xBEEF)));
        vm.setEnv("REVENUE_EPOCH_GENESIS_TS", "1700000000");
        vm.setEnv("REVENUE_EPOCH_LENGTH", "259200");
        vm.setEnv("REGENT_EMISSIONS_CHAIN_ID", "1");
    }

    function testDeployFromEnvCreatesMainnetController() external {
        MainnetRegentEmissionsController controller = script.deployFromEnv();

        assertEq(address(controller.regent()), address(regent));
        assertEq(address(controller.usdc()), address(usdc));
        assertEq(address(controller.subjectRegistry()), address(subjectRegistry));
        assertEq(controller.usdcTreasury(), address(0xCAFE));
        assertEq(controller.genesisTs(), 1_700_000_000);
        assertEq(controller.epochLength(), 259_200);
        assertEq(controller.localChainId(), 1);
        assertEq(controller.owner(), address(0xBEEF));
        assertTrue(controller.hasRole(controller.CREDIT_ROLE(), address(0xBEEF)));
        assertTrue(controller.hasRole(controller.EPOCH_PUBLISHER_ROLE(), address(0xBEEF)));
        assertTrue(controller.hasRole(controller.PAUSER_ROLE(), address(0xBEEF)));
    }
}
