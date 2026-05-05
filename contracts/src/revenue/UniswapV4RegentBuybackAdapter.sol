// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRegentBuybackAdapter} from "src/revenue/interfaces/IRegentBuybackAdapter.sol";

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable;
}

interface IPermit2Allowance {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract UniswapV4RegentBuybackAdapter is Owned, IRegentBuybackAdapter {
    using PoolIdLibrary for PoolKey;
    using SafeTransferLib for address;

    uint256 public constant MAX_DEADLINE_SECONDS = 1800;
    bytes1 internal constant COMMAND_V4_SWAP = 0x10;

    address public immutable override usdc;
    address public immutable weth;
    address public immutable override regent;
    address public immutable routerCaller;
    IUniversalRouter public immutable universalRouter;
    IPermit2Allowance public immutable permit2;

    PoolKey public usdcWethPoolKey;
    PoolKey public wethRegentPoolKey;
    bytes32 public immutable wethRegentPoolId;
    uint256 public deadlineSeconds = 300;

    event DeadlineSecondsSet(uint256 previousSeconds, uint256 newSeconds);

    modifier onlyRouterCaller() {
        require(msg.sender == routerCaller, "ONLY_FEE_ROUTER");
        _;
    }

    constructor(
        address owner_,
        address usdc_,
        address weth_,
        address regent_,
        address routerCaller_,
        address universalRouter_,
        address permit2_,
        PoolKey memory usdcWethPoolKey_,
        PoolKey memory wethRegentPoolKey_,
        bytes32 wethRegentPoolId_
    ) Owned(owner_) {
        require(usdc_ != address(0), "USDC_ZERO");
        require(weth_ != address(0), "WETH_ZERO");
        require(regent_ != address(0), "REGENT_ZERO");
        require(routerCaller_ != address(0), "FEE_ROUTER_ZERO");
        require(universalRouter_ != address(0), "UNIVERSAL_ROUTER_ZERO");
        require(permit2_ != address(0), "PERMIT2_ZERO");
        require(_poolContains(usdcWethPoolKey_, usdc_, weth_), "POOL_NOT_USDC_WETH");
        require(_poolContains(wethRegentPoolKey_, weth_, regent_), "POOL_NOT_WETH_REGENT");
        require(PoolId.unwrap(wethRegentPoolKey_.toId()) == wethRegentPoolId_, "POOL_ID_MISMATCH");

        usdc = usdc_;
        weth = weth_;
        regent = regent_;
        routerCaller = routerCaller_;
        universalRouter = IUniversalRouter(universalRouter_);
        permit2 = IPermit2Allowance(permit2_);
        usdcWethPoolKey = usdcWethPoolKey_;
        wethRegentPoolKey = wethRegentPoolKey_;
        wethRegentPoolId = wethRegentPoolId_;
    }

    function buyRegent(uint256 usdcAmount, uint256 minRegentOut, address recipient)
        external
        override
        onlyRouterCaller
        returns (uint256 regentOut)
    {
        require(usdcAmount != 0, "AMOUNT_ZERO");
        require(usdcAmount <= type(uint128).max, "AMOUNT_TOO_LARGE");
        require(minRegentOut != 0, "MIN_OUT_ZERO");
        require(minRegentOut <= type(uint128).max, "MIN_OUT_TOO_LARGE");
        require(recipient != address(0), "RECIPIENT_ZERO");

        uint256 beforeBalance = IERC20SupplyMinimal(regent).balanceOf(recipient);
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);

        _approveRouter(usdcAmount);
        _executeConfiguredSwap(uint128(usdcAmount), uint128(minRegentOut), recipient);

        uint256 afterBalance = IERC20SupplyMinimal(regent).balanceOf(recipient);
        regentOut = afterBalance - beforeBalance;
        require(regentOut >= minRegentOut, "REGENT_OUT_LOW");
    }

    function setDeadlineSeconds(uint256 newDeadlineSeconds) external onlyOwner {
        require(newDeadlineSeconds != 0, "DEADLINE_ZERO");
        require(newDeadlineSeconds <= MAX_DEADLINE_SECONDS, "DEADLINE_TOO_LONG");
        uint256 previous = deadlineSeconds;
        deadlineSeconds = newDeadlineSeconds;
        emit DeadlineSecondsSet(previous, newDeadlineSeconds);
    }

    function _approveRouter(uint256 usdcAmount) internal {
        usdc.forceApprove(address(permit2), usdcAmount);
        permit2.approve(
            usdc,
            address(universalRouter),
            uint160(usdcAmount),
            uint48(block.timestamp + deadlineSeconds)
        );
    }

    function _executeConfiguredSwap(uint128 usdcAmount, uint128 minRegentOut, address recipient)
        internal
    {
        PathKey[] memory path = new PathKey[](2);
        path[0] = PathKey({
            intermediateCurrency: Currency.wrap(weth),
            fee: usdcWethPoolKey.fee,
            tickSpacing: usdcWethPoolKey.tickSpacing,
            hooks: usdcWethPoolKey.hooks,
            hookData: bytes("")
        });
        path[1] = PathKey({
            intermediateCurrency: Currency.wrap(regent),
            fee: wethRegentPoolKey.fee,
            tickSpacing: wethRegentPoolKey.tickSpacing,
            hooks: wethRegentPoolKey.hooks,
            hookData: bytes("")
        });

        uint256[] memory minHopPriceX36 = new uint256[](0);
        IV4Router.ExactInputParams memory exactInput = IV4Router.ExactInputParams({
            currencyIn: Currency.wrap(usdc),
            path: path,
            minHopPriceX36: minHopPriceX36,
            amountIn: usdcAmount,
            amountOutMinimum: minRegentOut
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );
        bytes[] memory actionParams = new bytes[](3);
        actionParams[0] = abi.encode(exactInput);
        actionParams[1] = abi.encode(Currency.wrap(usdc), uint256(usdcAmount));
        actionParams[2] = abi.encode(Currency.wrap(regent), recipient, uint256(minRegentOut));

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, actionParams);

        bytes memory commands = abi.encodePacked(COMMAND_V4_SWAP);
        universalRouter.execute(commands, inputs, block.timestamp + deadlineSeconds);
    }

    function _poolContains(PoolKey memory poolKey, address tokenA, address tokenB)
        internal
        pure
        returns (bool)
    {
        address currency0 = Currency.unwrap(poolKey.currency0);
        address currency1 = Currency.unwrap(poolKey.currency1);
        return (currency0 == tokenA && currency1 == tokenB)
            || (currency0 == tokenB && currency1 == tokenA);
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc || token == regent || token == weth;
    }
}
