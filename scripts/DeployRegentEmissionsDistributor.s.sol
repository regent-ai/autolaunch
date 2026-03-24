// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {RegentEmissionsDistributorV2} from "src/revenue/RegentEmissionsDistributorV2.sol";

contract DeployRegentEmissionsDistributorScript is Script {
    struct ScriptConfig {
        address regentToken;
        address owner;
        uint256 epochGenesisTs;
        uint256 localChainId;
    }

    uint256 internal constant DEFAULT_ETHEREUM_MAINNET_CHAIN_ID = 1;

    function _loadConfig() internal view returns (ScriptConfig memory cfg) {
        cfg.regentToken = vm.envAddress("REGENT_TOKEN_ADDRESS");
        require(cfg.regentToken != address(0), "REGENT_TOKEN_ZERO");

        cfg.owner = _envAddressOr(
            "REGENT_EMISSIONS_OWNER",
            _envAddressOr("AUTOLAUNCH_RECOVERY_SAFE_ADDRESS", _envAddressOr("DEPLOYER", address(0)))
        );
        require(cfg.owner != address(0), "OWNER_ZERO");

        cfg.epochGenesisTs = vm.envOr(
            "REVENUE_EPOCH_GENESIS_TS", vm.envOr("AUTOLAUNCH_EPOCH_GENESIS_TS", block.timestamp)
        );
        require(cfg.epochGenesisTs > 0, "EPOCH_GENESIS_ZERO");

        cfg.localChainId = vm.envOr(
            "REGENT_EMISSIONS_CHAIN_ID",
            vm.envOr("ETH_CHAIN_ID", DEFAULT_ETHEREUM_MAINNET_CHAIN_ID)
        );
        require(cfg.localChainId > 0, "CHAIN_ID_ZERO");
    }

    function deployFromEnv() external returns (RegentEmissionsDistributorV2 distributor) {
        return _deployFromEnv();
    }

    function _deployFromEnv() internal returns (RegentEmissionsDistributorV2 distributor) {
        ScriptConfig memory cfg = _loadConfig();

        vm.startBroadcast();
        distributor =
            new RegentEmissionsDistributorV2({regent_: cfg.regentToken, genesisTs_: cfg.epochGenesisTs, owner_: cfg.owner});
        vm.stopBroadcast();

        string memory resultJson = string.concat(
            "REGENT_EMISSIONS_RESULT_JSON:{\"regentEmissionsDistributorAddress\":\"",
            vm.toString(address(distributor)),
            "\",\"regentTokenAddress\":\"",
            vm.toString(cfg.regentToken),
            "\",\"owner\":\"",
            vm.toString(cfg.owner),
            "\",\"epochGenesisTs\":",
            vm.toString(cfg.epochGenesisTs),
            ",\"localChainId\":",
            vm.toString(cfg.localChainId),
            "}"
        );
        console2.log(resultJson);
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
