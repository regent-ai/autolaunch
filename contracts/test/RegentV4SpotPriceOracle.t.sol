// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {
    AggregatorV3Interface,
    RegentV4SpotPriceOracle
} from "src/revenue/RegentV4SpotPriceOracle.sol";
import {IRegentUsdOracle} from "src/revenue/interfaces/IRegentUsdOracle.sol";

contract MockV4StatePoolManager {
    mapping(bytes32 => bytes32) public slots;

    function setPoolState(PoolId poolId, uint160 sqrtPriceX96, int24 tick, uint128 liquidity)
        external
    {
        bytes32 stateSlot = _poolStateSlot(poolId);
        slots[stateSlot] = bytes32(uint256(sqrtPriceX96) | (uint256(uint24(tick)) << 160));
        slots[bytes32(uint256(stateSlot) + 3)] = bytes32(uint256(liquidity));
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return slots[slot];
    }

    function _poolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(uint256(6))));
    }
}

contract MockAggregatorV3 {
    uint8 public decimals;
    uint80 public roundId = 1;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound = 1;

    constructor(uint8 decimals_, int256 answer_, uint256 timestamp_) {
        decimals = decimals_;
        answer = answer_;
        startedAt = timestamp_;
        updatedAt = timestamp_;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
    }

    function setStartedAt(uint256 startedAt_) external {
        startedAt = startedAt_;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

contract RegentV4SpotPriceOracleTest is Test {
    using PoolIdLibrary for PoolKey;

    address internal constant OWNER = address(0xA11CE);
    address internal constant REGENT = address(0x1000);
    address internal constant WETH = address(0x2000);
    address internal constant OTHER = address(0x3000);
    uint160 internal constant ONE_TO_ONE_SQRT_PRICE_X96 = 2 ** 96;
    uint128 internal constant LIQUIDITY = 1_000_000;

    MockV4StatePoolManager internal poolManager;
    MockAggregatorV3 internal ethUsdFeed;
    MockAggregatorV3 internal sequencerFeed;
    PoolKey internal regentCurrency0Key;
    PoolKey internal regentCurrency1Key;

    function setUp() external {
        vm.warp(10_000);
        poolManager = new MockV4StatePoolManager();
        ethUsdFeed = new MockAggregatorV3(8, 2000e8, block.timestamp);
        sequencerFeed = new MockAggregatorV3(0, 0, block.timestamp - 2 hours);
        regentCurrency0Key = _poolKey(REGENT, WETH);
        regentCurrency1Key = _poolKey(WETH, REGENT);
        poolManager.setPoolState(regentCurrency0Key.toId(), ONE_TO_ONE_SQRT_PRICE_X96, 0, LIQUIDITY);
        poolManager.setPoolState(regentCurrency1Key.toId(), ONE_TO_ONE_SQRT_PRICE_X96, 0, LIQUIDITY);
    }

    function testConstructorRejectsPoolIdMismatch() external {
        vm.expectRevert("POOL_ID_MISMATCH");
        _oracle(regentCurrency0Key, bytes32(uint256(1)));
    }

    function testConstructorRejectsPoolThatIsNotWethRegent() external {
        PoolKey memory badKey = _poolKey(REGENT, OTHER);

        vm.expectRevert("POOL_NOT_WETH_REGENT");
        _oracle(badKey, PoolId.unwrap(badKey.toId()));
    }

    function testEthUsdStaleAnswerReverts() external {
        RegentV4SpotPriceOracle oracle =
            _oracle(regentCurrency0Key, PoolId.unwrap(regentCurrency0Key.toId()));
        ethUsdFeed.setUpdatedAt(block.timestamp - 2 hours);

        vm.expectRevert("ETH_USD_STALE");
        oracle.quoteRegentForUsdc(100e6);
    }

    function testSequencerDownAndGracePeriodRevert() external {
        RegentV4SpotPriceOracle oracle =
            _oracle(regentCurrency0Key, PoolId.unwrap(regentCurrency0Key.toId()));

        sequencerFeed.setAnswer(1);
        vm.expectRevert("SEQUENCER_DOWN");
        oracle.quoteRegentForUsdc(100e6);

        sequencerFeed.setAnswer(0);
        sequencerFeed.setStartedAt(block.timestamp - 10 minutes);
        vm.expectRevert("SEQUENCER_GRACE");
        oracle.quoteRegentForUsdc(100e6);
    }

    function testPoolStateAndPriceBoundsRevert() external {
        RegentV4SpotPriceOracle oracle =
            _oracle(regentCurrency0Key, PoolId.unwrap(regentCurrency0Key.toId()));

        poolManager.setPoolState(regentCurrency0Key.toId(), 0, 0, LIQUIDITY);
        vm.expectRevert("POOL_UNINITIALIZED");
        oracle.quoteRegentForUsdc(100e6);

        poolManager.setPoolState(regentCurrency0Key.toId(), ONE_TO_ONE_SQRT_PRICE_X96, 0, 1);
        vm.expectRevert("POOL_LIQUIDITY_LOW");
        oracle.quoteRegentForUsdc(100e6);

        poolManager.setPoolState(regentCurrency0Key.toId(), ONE_TO_ONE_SQRT_PRICE_X96, 0, LIQUIDITY);
        vm.prank(OWNER);
        oracle.setRegentUsdBounds(3000e18, 4000e18);
        vm.expectRevert("REGENT_PRICE_TOO_LOW");
        oracle.quoteRegentForUsdc(100e6);

        vm.prank(OWNER);
        oracle.setRegentUsdBounds(1e18, 1000e18);
        vm.expectRevert("REGENT_PRICE_TOO_HIGH");
        oracle.quoteRegentForUsdc(100e6);
    }

    function testPriceConversionWorksForRegentAsCurrency0() external {
        RegentV4SpotPriceOracle oracle =
            _oracle(regentCurrency0Key, PoolId.unwrap(regentCurrency0Key.toId()));

        IRegentUsdOracle.Quote memory quote = oracle.quoteRegentForUsdc(100e6);

        assertEq(quote.regentUsdE18, 2000e18);
        assertEq(quote.ethUsdE18, 2000e18);
        assertEq(quote.regentAmount, 0.05e18);
        assertEq(quote.regentWethLiquidity, LIQUIDITY);
    }

    function testPriceConversionWorksForRegentAsCurrency1() external {
        RegentV4SpotPriceOracle oracle =
            _oracle(regentCurrency1Key, PoolId.unwrap(regentCurrency1Key.toId()));

        IRegentUsdOracle.Quote memory quote = oracle.quoteRegentForUsdc(100e6);

        assertEq(quote.regentUsdE18, 2000e18);
        assertEq(quote.regentAmount, 0.05e18);
    }

    function _oracle(PoolKey memory poolKey, bytes32 configuredPoolId)
        internal
        returns (RegentV4SpotPriceOracle)
    {
        return new RegentV4SpotPriceOracle(
            OWNER,
            IPoolManager(address(poolManager)),
            poolKey,
            configuredPoolId,
            REGENT,
            WETH,
            AggregatorV3Interface(address(ethUsdFeed)),
            AggregatorV3Interface(address(sequencerFeed)),
            1e18,
            3000e18,
            100,
            1 hours,
            1 hours
        );
    }

    function _poolKey(address currency0, address currency1) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }
}
