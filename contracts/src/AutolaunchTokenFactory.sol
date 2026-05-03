// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AutolaunchLaunchToken} from "src/AutolaunchLaunchToken.sol";
import {ITokenFactory} from "src/interfaces/ITokenFactory.sol";

contract AutolaunchTokenFactory is ITokenFactory {
    event TokenCreated(
        address indexed token,
        string name,
        string symbol,
        uint8 decimals,
        uint256 totalSupply,
        address indexed recipient,
        bytes32 indexed salt
    );

    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 totalSupply,
        address recipient,
        bytes calldata configData,
        bytes32 salt
    ) external returns (address token) {
        require(bytes(name).length != 0, "NAME_EMPTY");
        require(bytes(symbol).length != 0, "SYMBOL_EMPTY");
        require(decimals == 18, "DECIMALS_MUST_BE_18");
        require(totalSupply != 0, "SUPPLY_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(configData.length == 0, "CONFIG_DATA_NONEMPTY");

        token = address(new AutolaunchLaunchToken{salt: salt}(name, symbol, totalSupply, recipient));

        emit TokenCreated(token, name, symbol, decimals, totalSupply, recipient, salt);
    }
}
