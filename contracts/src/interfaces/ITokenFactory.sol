// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ITokenFactory {
    function createToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        uint256 totalSupply,
        address owner,
        bytes calldata configData,
        bytes32 salt
    ) external returns (address token);
}
