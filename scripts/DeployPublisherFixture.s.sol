// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SimpleMintableERC20} from "src/SimpleMintableERC20.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";
import {RevenueShareFactory} from "src/revenue/RevenueShareFactory.sol";
import {RevenueIngressRouter} from "src/revenue/RevenueIngressRouter.sol";
import {RevenueIngressFactory} from "src/revenue/RevenueIngressFactory.sol";
import {RegentEmissionsDistributorV2} from "src/revenue/RegentEmissionsDistributorV2.sol";

contract DeployPublisherFixtureScript is Script {
    function run() external returns (bytes memory) {
        address admin = vm.envAddress("PUBLISHER_FIXTURE_ADMIN_ADDRESS");
        address publisher = _envAddressOr("PUBLISHER_FIXTURE_PUBLISHER", admin);
        address stakerOne = _envAddressOr("PUBLISHER_FIXTURE_STAKER_ONE", admin);
        address stakerTwo = _envAddressOr("PUBLISHER_FIXTURE_STAKER_TWO", admin);
        address emissionRecipient = _envAddressOr("PUBLISHER_FIXTURE_EMISSION_RECIPIENT", stakerOne);
        uint256 agentId = vm.envOr("PUBLISHER_FIXTURE_AGENT_ID", uint256(42));
        uint256 genesisTs = vm.envOr("PUBLISHER_FIXTURE_GENESIS_TS", block.timestamp);

        vm.startBroadcast();

        SimpleMintableERC20 usdc =
            new SimpleMintableERC20("Fixture USDC", "USDC", 6, admin, 1_000_000_000_000, admin);
        SimpleMintableERC20 regent =
            new SimpleMintableERC20("Fixture Regent", "REGENT", 18, publisher, 1_000_000 ether, admin);
        SimpleMintableERC20 stakeToken =
            new SimpleMintableERC20("Fixture Agent Coin", "FAG", 18, stakerOne, 1_000_000 ether, admin);

        stakeToken.mint(stakerTwo, 1_000_000 ether);

        SubjectRegistry subjectRegistry = new SubjectRegistry(admin);
        RevenueShareFactory revenueShareFactory =
            new RevenueShareFactory(admin, subjectRegistry);
        RevenueIngressRouter revenueIngressRouter =
            new RevenueIngressRouter(admin, subjectRegistry);
        RevenueIngressFactory revenueIngressFactory = new RevenueIngressFactory(admin);
        subjectRegistry.transferOwnership(address(revenueShareFactory));

        bytes32 subjectId = keccak256(abi.encode(block.chainid, address(stakeToken)));
        address[] memory initialRewardTokens = new address[](1);
        initialRewardTokens[0] = address(usdc);
        address splitter = revenueShareFactory.createSubjectSplitter(
            subjectId,
            address(stakeToken),
            admin,
            admin,
            admin,
            admin,
            block.chainid,
            emissionRecipient,
            100,
            "Fixture Subject",
            initialRewardTokens
        );

        subjectRegistry.linkIdentity(subjectId, block.chainid, address(0x8004), agentId);

        address ingress = revenueIngressFactory.createIngressAccount(
            splitter,
            admin,
            keccak256("fixture_ingress"),
            keccak256(abi.encode(subjectId, "fixture"))
        );

        RegentEmissionsDistributorV2 distributor =
            new RegentEmissionsDistributorV2(address(regent), genesisTs, publisher);

        vm.stopBroadcast();

        console2.log(
            string.concat(
                "PUBLISHER_FIXTURE_JSON:{\"distributor\":\"",
                vm.toString(address(distributor)),
                "\",\"regent\":\"",
                vm.toString(address(regent)),
                "\",\"usdc\":\"",
                vm.toString(address(usdc)),
                "\",\"subjectRegistry\":\"",
                vm.toString(address(subjectRegistry)),
                "\",\"revenueShareFactory\":\"",
                vm.toString(address(revenueShareFactory)),
                "\",\"revenueIngressRouter\":\"",
                vm.toString(address(revenueIngressRouter)),
                "\",\"revenueIngressFactory\":\"",
                vm.toString(address(revenueIngressFactory)),
                "\",\"splitter\":\"",
                vm.toString(splitter),
                "\",\"ingress\":\"",
                vm.toString(ingress),
                "\",\"subjectId\":\"",
                vm.toString(subjectId),
                "\",\"publisher\":\"",
                vm.toString(publisher),
                "\",\"emissionRecipient\":\"",
                vm.toString(emissionRecipient),
                "\"}"
            )
        );

        return "";
    }

    function _envAddressOr(string memory key, address fallbackValue)
        internal
        view
        returns (address)
    {
        try vm.envAddress(key) returns (address value) {
            return value;
        } catch {
            return fallbackValue;
        }
    }
}
