// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IRegentRevenueFeeRouter} from "src/revenue/interfaces/IRegentRevenueFeeRouter.sol";

contract MockRegentRevenueFeeRouter is IRegentRevenueFeeRouter {
    using SafeTransferLib for address;

    address public immutable override usdc;
    address public immutable override regent;
    uint16 public override protocolSkimBps = 1000;
    bool public shouldRevert;
    uint256 public totalUsdcProcessed;
    uint256 public totalRegentOwed;
    uint256 public totalRegentBought;

    constructor(address usdc_, address regent_) {
        usdc = usdc_;
        regent = regent_;
    }

    function setProtocolSkimBps(uint16 newBps) external {
        protocolSkimBps = newBps;
    }

    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    function processProtocolFee(bytes32, address, uint256 usdcAmount, bytes32)
        external
        override
        returns (uint256 regentOwed, uint256 regentBought)
    {
        require(!shouldRevert, "MOCK_ROUTER_REVERT");
        totalUsdcProcessed += usdcAmount;
        regentOwed = usdcAmount * 1e12;
        regentBought = regentOwed;
        totalRegentOwed += regentOwed;
        totalRegentBought += regentBought;
    }
}
