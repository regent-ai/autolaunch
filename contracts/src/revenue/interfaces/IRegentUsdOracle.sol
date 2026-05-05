// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRegentUsdOracle {
    struct Quote {
        uint256 usdcAmount;
        uint256 regentAmount;
        uint256 regentUsdE18;
        uint256 ethUsdE18;
        int24 regentWethTick;
        uint128 regentWethLiquidity;
    }

    function quoteRegentForUsdc(uint256 usdcAmount)
        external
        view
        returns (Quote memory quote);
}
