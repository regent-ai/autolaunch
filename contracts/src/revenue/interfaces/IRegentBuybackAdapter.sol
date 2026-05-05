// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRegentBuybackAdapter {
    function usdc() external view returns (address);
    function regent() external view returns (address);

    function buyRegent(uint256 usdcAmount, uint256 minRegentOut, address recipient)
        external
        returns (uint256 regentOut);
}
