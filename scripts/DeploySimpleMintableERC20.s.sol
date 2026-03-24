// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {SimpleMintableERC20} from "src/SimpleMintableERC20.sol";

contract DeploySimpleMintableERC20Script is Script {
    struct ScriptConfig {
        string name;
        string symbol;
        uint8 decimals;
        address owner;
        address initialRecipient;
        uint256 initialSupply;
    }

    function _loadConfig() internal view returns (ScriptConfig memory cfg) {
        cfg.name = vm.envOr("TOKEN_NAME", string("Autolaunch Test Token"));
        cfg.symbol = vm.envOr("TOKEN_SYMBOL", string("AUT"));
        cfg.decimals = uint8(vm.envOr("TOKEN_DECIMALS", uint256(18)));

        cfg.owner = _envAddressOr("TOKEN_OWNER", _envAddressOr("DEPLOYER", address(0)));
        require(cfg.owner != address(0), "OWNER_ZERO");

        cfg.initialRecipient =
            _envAddressOr("TOKEN_INITIAL_RECIPIENT", _envAddressOr("DEPLOYER", address(0)));
        require(cfg.initialRecipient != address(0), "RECIPIENT_ZERO");

        uint256 wholeTokens = vm.envOr("TOKEN_INITIAL_SUPPLY", uint256(1_000_000));
        cfg.initialSupply = wholeTokens * (10 ** cfg.decimals);
    }

    function deployFromEnv() external returns (SimpleMintableERC20 token) {
        return _deployFromEnv();
    }

    function _deployFromEnv() internal returns (SimpleMintableERC20 token) {
        ScriptConfig memory cfg = _loadConfig();

        vm.startBroadcast();
        token = new SimpleMintableERC20({
            name_: cfg.name,
            symbol_: cfg.symbol,
            decimals_: cfg.decimals,
            initialRecipient_: cfg.initialRecipient,
            initialSupply_: cfg.initialSupply,
            owner_: cfg.owner
        });
        vm.stopBroadcast();

        console2.log(
            string.concat(
                "SIMPLE_ERC20_RESULT_JSON:{\"tokenAddress\":\"",
                vm.toString(address(token)),
                "\",\"owner\":\"",
                vm.toString(cfg.owner),
                "\",\"initialRecipient\":\"",
                vm.toString(cfg.initialRecipient),
                "\",\"initialSupply\":\"",
                vm.toString(cfg.initialSupply),
                "\",\"name\":\"",
                cfg.name,
                "\",\"symbol\":\"",
                cfg.symbol,
                "\"}"
            )
        );
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
