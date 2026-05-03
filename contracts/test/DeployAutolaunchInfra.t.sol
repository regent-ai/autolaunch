// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployAutolaunchInfraScript} from "scripts/DeployAutolaunchInfra.s.sol";
import {AutolaunchLaunchToken} from "src/AutolaunchLaunchToken.sol";
import {AutolaunchTokenFactory} from "src/AutolaunchTokenFactory.sol";
import {RegentLBPStrategyFactory} from "src/RegentLBPStrategyFactory.sol";
import {RevenueIngressFactory} from "src/revenue/RevenueIngressFactory.sol";
import {RevenueShareFactory} from "src/revenue/RevenueShareFactory.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";

contract DeployAutolaunchInfraScriptTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant DEPLOYER = address(0xBEEF);
    address internal constant TOKEN_RECIPIENT = address(0xCAFE);
    address internal constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    DeployAutolaunchInfraScript internal script;

    function setUp() external {
        script = new DeployAutolaunchInfraScript();
        vm.chainId(84_532);
    }

    function testDeployCreatesInfraAndTransfersRegistryOwnership() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({owner: OWNER, usdc: USDC});

        (
            SubjectRegistry subjectRegistry,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        ) = script.deploy(cfg);

        assertEq(subjectRegistry.owner(), address(revenueShareFactory));
        assertEq(revenueShareFactory.owner(), OWNER);
        assertEq(revenueShareFactory.pendingOwner(), address(0));
        assertEq(revenueIngressFactory.owner(), OWNER);
        assertEq(strategyFactory.owner(), OWNER);
        assertEq(revenueShareFactory.usdc(), USDC);
        assertEq(revenueIngressFactory.usdc(), USDC);
        assertEq(address(revenueShareFactory.subjectRegistry()), address(subjectRegistry));
        assertEq(revenueIngressFactory.subjectRegistry(), address(subjectRegistry));
        assertTrue(address(strategyFactory) != address(0));
        assertTrue(address(tokenFactory).code.length > 0);

        address launchToken = tokenFactory.createToken(
            "Regent Agent Token", "RAGENT", 18, 100_000_000_000e18, TOKEN_RECIPIENT, bytes(""), 0
        );
        AutolaunchLaunchToken token = AutolaunchLaunchToken(launchToken);
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100_000_000_000e18);
        assertEq(token.balanceOf(TOKEN_RECIPIENT), 100_000_000_000e18);
    }

    function testDeploySupportsAnyConfiguredOwner() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({owner: DEPLOYER, usdc: USDC});

        (
            ,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        ) = script.deploy(cfg);

        assertEq(revenueShareFactory.owner(), DEPLOYER);
        assertEq(revenueShareFactory.pendingOwner(), address(0));
        assertEq(revenueIngressFactory.owner(), DEPLOYER);
        assertEq(strategyFactory.owner(), DEPLOYER);
        assertTrue(address(tokenFactory).code.length > 0);
    }

    function testLoadConfigFromEnvReadsExplicitOwnerAndUsdc() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_USDC_ADDRESS", vm.toString(USDC));

        DeployAutolaunchInfraScript.ScriptConfig memory cfg = script.loadConfigFromEnv();

        assertEq(cfg.owner, OWNER);
        assertEq(cfg.usdc, USDC);
    }

    function testDeployFromEnvUsesLoadedConfig() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_USDC_ADDRESS", vm.toString(USDC));

        (
            SubjectRegistry subjectRegistry,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        ) = script.deployFromEnv();

        assertEq(subjectRegistry.owner(), address(revenueShareFactory));
        assertEq(revenueShareFactory.owner(), OWNER);
        assertEq(revenueShareFactory.pendingOwner(), address(0));
        assertEq(revenueIngressFactory.owner(), OWNER);
        assertEq(strategyFactory.owner(), OWNER);
        assertEq(revenueShareFactory.usdc(), USDC);
        assertTrue(address(strategyFactory) != address(0));
        assertTrue(address(tokenFactory).code.length > 0);
    }

    function testRunUsesSingleBroadcastPath() external {
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_USDC_ADDRESS", vm.toString(USDC));

        script.run();
    }

    function testValidateConfigRejectsWrongBaseSepoliaUsdc() external {
        DeployAutolaunchInfraScript.ScriptConfig memory cfg =
            DeployAutolaunchInfraScript.ScriptConfig({owner: OWNER, usdc: address(0xC0FFEE)});

        vm.expectRevert("USDC_NOT_CANONICAL");
        script.validateConfig(cfg);
    }

    function testLoadConfigFromEnvRejectsNonBaseChain() external {
        vm.chainId(1);
        vm.setEnv("AUTOLAUNCH_INFRA_OWNER", "0x00000000000000000000000000000000000A11CE");
        vm.setEnv("AUTOLAUNCH_USDC_ADDRESS", vm.toString(USDC));

        vm.expectRevert("BASE_CHAIN_ONLY");
        script.loadConfigFromEnv();
    }
}
