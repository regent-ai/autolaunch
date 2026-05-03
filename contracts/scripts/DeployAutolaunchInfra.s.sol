// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {AutolaunchTokenFactory} from "src/AutolaunchTokenFactory.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";
import {RevenueShareFactory} from "src/revenue/RevenueShareFactory.sol";
import {RevenueShareSplitterDeployer} from "src/revenue/RevenueShareSplitterDeployer.sol";
import {RevenueIngressFactory} from "src/revenue/RevenueIngressFactory.sol";
import {RegentLBPStrategyFactory} from "src/RegentLBPStrategyFactory.sol";
import {BaseUsdc} from "src/libraries/BaseUsdc.sol";

contract DeployAutolaunchInfraScript is Script {
    struct ScriptConfig {
        address owner;
        address usdc;
    }

    function deployFromEnv()
        external
        returns (
            SubjectRegistry subjectRegistry,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        )
    {
        ScriptConfig memory cfg = loadConfigFromEnv();

        return deploy(cfg);
    }

    function deploy(ScriptConfig memory cfg)
        public
        returns (
            SubjectRegistry subjectRegistry,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        )
    {
        validateConfig(cfg);

        vm.startBroadcast(cfg.owner);
        subjectRegistry = new SubjectRegistry(cfg.owner);
        RevenueShareSplitterDeployer splitterDeployer = new RevenueShareSplitterDeployer();
        revenueShareFactory =
            new RevenueShareFactory(cfg.owner, cfg.usdc, subjectRegistry, splitterDeployer);
        revenueIngressFactory =
            new RevenueIngressFactory(cfg.usdc, address(subjectRegistry), cfg.owner);
        strategyFactory = new RegentLBPStrategyFactory(cfg.owner);
        tokenFactory = new AutolaunchTokenFactory();
        subjectRegistry.transferOwnership(address(revenueShareFactory));
        revenueShareFactory.acceptSubjectRegistryOwnership();
        vm.stopBroadcast();
    }

    function validateConfig(ScriptConfig memory cfg) public view {
        require(cfg.owner != address(0), "OWNER_ZERO");
        require(cfg.usdc != address(0), "USDC_ZERO");
        BaseUsdc.requireCanonical(cfg.usdc);
    }

    function loadConfigFromEnv() public view returns (ScriptConfig memory cfg) {
        cfg.owner = vm.envAddress("AUTOLAUNCH_INFRA_OWNER");

        cfg.usdc = vm.envAddress("AUTOLAUNCH_USDC_ADDRESS");
        validateConfig(cfg);
    }

    function run() external {
        ScriptConfig memory cfg = loadConfigFromEnv();

        (
            SubjectRegistry subjectRegistry,
            RevenueShareFactory revenueShareFactory,
            RevenueIngressFactory revenueIngressFactory,
            RegentLBPStrategyFactory strategyFactory,
            AutolaunchTokenFactory tokenFactory
        ) = deploy(cfg);

        console2.log(
            string.concat(
                "AUTOLAUNCH_INFRA_RESULT_JSON:{\"subjectRegistryAddress\":\"",
                vm.toString(address(subjectRegistry)),
                "\",\"revenueShareFactoryAddress\":\"",
                vm.toString(address(revenueShareFactory)),
                "\",\"revenueIngressFactoryAddress\":\"",
                vm.toString(address(revenueIngressFactory)),
                "\",\"strategyFactoryAddress\":\"",
                vm.toString(address(strategyFactory)),
                "\",\"tokenFactoryAddress\":\"",
                vm.toString(address(tokenFactory)),
                "\",\"usdcAddress\":\"",
                vm.toString(cfg.usdc),
                "\",\"revenueShareFactoryOwner\":\"",
                vm.toString(revenueShareFactory.owner()),
                "\",\"revenueShareFactoryPendingOwner\":\"",
                vm.toString(revenueShareFactory.pendingOwner()),
                "\",\"revenueIngressFactoryOwner\":\"",
                vm.toString(revenueIngressFactory.owner()),
                "\",\"strategyFactoryOwner\":\"",
                vm.toString(strategyFactory.owner()),
                "\",\"owner\":\"",
                vm.toString(cfg.owner),
                "\"}"
            )
        );
    }
}
