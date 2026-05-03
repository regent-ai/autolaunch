// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AutolaunchLaunchToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address recipient_
    ) ERC20(name_, symbol_) {
        require(bytes(name_).length != 0, "NAME_EMPTY");
        require(bytes(symbol_).length != 0, "SYMBOL_EMPTY");
        require(totalSupply_ != 0, "SUPPLY_ZERO");
        require(recipient_ != address(0), "RECIPIENT_ZERO");

        _mint(recipient_, totalSupply_);
    }
}
