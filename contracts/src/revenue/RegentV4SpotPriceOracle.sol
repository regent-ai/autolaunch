// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Owned} from "src/auth/Owned.sol";
import {IRegentUsdOracle} from "src/revenue/interfaces/IRegentUsdOracle.sol";

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract RegentV4SpotPriceOracle is Owned, IRegentUsdOracle {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;
    PoolKey public regentWethPoolKey;
    PoolId public immutable regentWethPoolId;
    address public immutable regent;
    address public immutable weth;
    AggregatorV3Interface public immutable ethUsdFeed;
    AggregatorV3Interface public immutable sequencerUptimeFeed;
    uint256 public maxEthUsdStalenessSeconds;
    uint256 public sequencerGracePeriodSeconds;
    uint256 public minRegentUsdE18;
    uint256 public maxRegentUsdE18;
    uint128 public minRegentWethLiquidity;

    event RegentUsdBoundsSet(uint256 minRegentUsdE18, uint256 maxRegentUsdE18);
    event MinRegentWethLiquiditySet(uint128 minRegentWethLiquidity);
    event StalenessSet(uint256 maxEthUsdStalenessSeconds, uint256 sequencerGracePeriodSeconds);

    constructor(
        address owner_,
        IPoolManager poolManager_,
        PoolKey memory regentWethPoolKey_,
        bytes32 configuredPoolId,
        address regent_,
        address weth_,
        AggregatorV3Interface ethUsdFeed_,
        AggregatorV3Interface sequencerUptimeFeed_,
        uint256 minRegentUsdE18_,
        uint256 maxRegentUsdE18_,
        uint128 minRegentWethLiquidity_,
        uint256 maxEthUsdStalenessSeconds_,
        uint256 sequencerGracePeriodSeconds_
    ) Owned(owner_) {
        require(address(poolManager_) != address(0), "POOL_MANAGER_ZERO");
        require(regent_ != address(0), "REGENT_ZERO");
        require(weth_ != address(0), "WETH_ZERO");
        require(regent_ != weth_, "REGENT_IS_WETH");
        require(address(ethUsdFeed_) != address(0), "ETH_USD_FEED_ZERO");
        require(address(sequencerUptimeFeed_) != address(0), "SEQUENCER_FEED_ZERO");
        require(maxEthUsdStalenessSeconds_ != 0, "STALENESS_ZERO");
        _validateBounds(minRegentUsdE18_, maxRegentUsdE18_);

        PoolId actual = regentWethPoolKey_.toId();
        require(PoolId.unwrap(actual) == configuredPoolId, "POOL_ID_MISMATCH");
        require(_isWethRegentPool(regentWethPoolKey_, regent_, weth_), "POOL_NOT_WETH_REGENT");

        poolManager = poolManager_;
        regentWethPoolKey = regentWethPoolKey_;
        regentWethPoolId = actual;
        regent = regent_;
        weth = weth_;
        ethUsdFeed = ethUsdFeed_;
        sequencerUptimeFeed = sequencerUptimeFeed_;
        minRegentUsdE18 = minRegentUsdE18_;
        maxRegentUsdE18 = maxRegentUsdE18_;
        minRegentWethLiquidity = minRegentWethLiquidity_;
        maxEthUsdStalenessSeconds = maxEthUsdStalenessSeconds_;
        sequencerGracePeriodSeconds = sequencerGracePeriodSeconds_;
    }

    function quoteRegentForUsdc(uint256 usdcAmount)
        external
        view
        override
        returns (IRegentUsdOracle.Quote memory quote)
    {
        require(usdcAmount != 0, "AMOUNT_ZERO");

        _checkSequencer();
        uint256 ethUsdE18 = _readEthUsdE18();

        (uint160 sqrtPriceX96, int24 tick,,) = StateLibrary.getSlot0(poolManager, regentWethPoolId);
        require(sqrtPriceX96 != 0, "POOL_UNINITIALIZED");

        uint128 liquidity = StateLibrary.getLiquidity(poolManager, regentWethPoolId);
        require(liquidity >= minRegentWethLiquidity, "POOL_LIQUIDITY_LOW");

        uint256 wethPerRegentE18 = _wethPerRegentE18(sqrtPriceX96);
        uint256 regentUsdE18 = FullMath.mulDiv(wethPerRegentE18, ethUsdE18, 1e18);
        require(regentUsdE18 >= minRegentUsdE18, "REGENT_PRICE_TOO_LOW");
        require(regentUsdE18 <= maxRegentUsdE18, "REGENT_PRICE_TOO_HIGH");

        uint256 usdcUsdE18 = usdcAmount * 1e12;
        uint256 regentAmount = FullMath.mulDiv(usdcUsdE18, 1e18, regentUsdE18);

        quote = IRegentUsdOracle.Quote({
            usdcAmount: usdcAmount,
            regentAmount: regentAmount,
            regentUsdE18: regentUsdE18,
            ethUsdE18: ethUsdE18,
            regentWethTick: tick,
            regentWethLiquidity: liquidity
        });
    }

    function setRegentUsdBounds(uint256 minRegentUsdE18_, uint256 maxRegentUsdE18_)
        external
        onlyOwner
    {
        _validateBounds(minRegentUsdE18_, maxRegentUsdE18_);
        minRegentUsdE18 = minRegentUsdE18_;
        maxRegentUsdE18 = maxRegentUsdE18_;
        emit RegentUsdBoundsSet(minRegentUsdE18_, maxRegentUsdE18_);
    }

    function setMinRegentWethLiquidity(uint128 minLiquidity) external onlyOwner {
        minRegentWethLiquidity = minLiquidity;
        emit MinRegentWethLiquiditySet(minLiquidity);
    }

    function setStaleness(uint256 maxEthUsdStalenessSeconds_, uint256 sequencerGracePeriodSeconds_)
        external
        onlyOwner
    {
        require(maxEthUsdStalenessSeconds_ != 0, "STALENESS_ZERO");
        maxEthUsdStalenessSeconds = maxEthUsdStalenessSeconds_;
        sequencerGracePeriodSeconds = sequencerGracePeriodSeconds_;
        emit StalenessSet(maxEthUsdStalenessSeconds_, sequencerGracePeriodSeconds_);
    }

    function _checkSequencer() internal view {
        (, int256 answer, uint256 startedAt,,) = sequencerUptimeFeed.latestRoundData();
        require(answer == 0, "SEQUENCER_DOWN");
        require(block.timestamp >= startedAt + sequencerGracePeriodSeconds, "SEQUENCER_GRACE");
    }

    function _readEthUsdE18() internal view returns (uint256) {
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
            ethUsdFeed.latestRoundData();
        require(answer > 0, "ETH_USD_INVALID");
        require(answeredInRound >= roundId, "ETH_USD_INCOMPLETE");
        require(updatedAt != 0, "ETH_USD_MISSING");
        require(updatedAt + maxEthUsdStalenessSeconds >= block.timestamp, "ETH_USD_STALE");

        uint8 decimals = ethUsdFeed.decimals();
        uint256 unsignedAnswer = uint256(answer);
        if (decimals == 18) {
            return unsignedAnswer;
        }
        if (decimals < 18) {
            return unsignedAnswer * (10 ** (18 - decimals));
        }
        return unsignedAnswer / (10 ** (decimals - 18));
    }

    function _wethPerRegentE18(uint160 sqrtPriceX96) internal view returns (uint256) {
        uint256 q96 = 2 ** 96;
        uint256 priceX96 = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), q96);
        uint256 priceE18 = FullMath.mulDiv(priceX96, 1e18, q96);
        require(priceE18 != 0, "POOL_PRICE_ZERO");

        bool regentIsCurrency0 = Currency.unwrap(regentWethPoolKey.currency0) == regent;
        if (regentIsCurrency0) {
            return priceE18;
        }

        return FullMath.mulDiv(1e18, 1e18, priceE18);
    }

    function _isWethRegentPool(PoolKey memory poolKey, address regent_, address weth_)
        internal
        pure
        returns (bool)
    {
        address currency0 = Currency.unwrap(poolKey.currency0);
        address currency1 = Currency.unwrap(poolKey.currency1);
        return (currency0 == regent_ && currency1 == weth_)
            || (currency0 == weth_ && currency1 == regent_);
    }

    function _validateBounds(uint256 minRegentUsdE18_, uint256 maxRegentUsdE18_) internal pure {
        require(minRegentUsdE18_ != 0, "MIN_PRICE_ZERO");
        require(maxRegentUsdE18_ >= minRegentUsdE18_, "PRICE_BOUNDS_INVALID");
    }
}
