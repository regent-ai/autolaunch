// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {UniswapV4RegentBuybackAdapter} from "src/revenue/UniswapV4RegentBuybackAdapter.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract MockPermit2Allowance {
    address public lastToken;
    address public lastSpender;
    uint160 public lastAmount;
    uint48 public lastExpiration;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        lastToken = token;
        lastSpender = spender;
        lastAmount = amount;
        lastExpiration = expiration;
    }
}

contract MockUniversalRouter {
    bytes public lastCommands;
    bytes[] public lastInputs;
    uint256 public lastDeadline;
    address public immutable regent;
    uint256 public outputAmount;

    constructor(address regent_) {
        regent = regent_;
    }

    function setOutputAmount(uint256 outputAmount_) external {
        outputAmount = outputAmount_;
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable
    {
        lastCommands = commands;
        delete lastInputs;
        for (uint256 i; i < inputs.length; ++i) {
            lastInputs.push(inputs[i]);
        }
        lastDeadline = deadline;

        (, bytes[] memory actionParams) = abi.decode(inputs[0], (bytes, bytes[]));
        (, address recipient,) = abi.decode(actionParams[2], (Currency, address, uint256));
        MintableERC20Mock(regent).transfer(recipient, outputAmount);
    }
}

contract UniswapV4RegentBuybackAdapterTest is Test {
    using PoolIdLibrary for PoolKey;

    address internal constant OWNER = address(0xA11CE);
    address internal constant FEE_ROUTER = address(0x1111);
    address internal constant RECIPIENT = address(0x2222);

    MintableERC20Mock internal usdc;
    MintableERC20Mock internal weth;
    MintableERC20Mock internal regent;
    MockUniversalRouter internal universalRouter;
    MockPermit2Allowance internal permit2;
    PoolKey internal usdcWethPoolKey;
    PoolKey internal wethRegentPoolKey;
    UniswapV4RegentBuybackAdapter internal adapter;

    function setUp() external {
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        weth = new MintableERC20Mock("Wrapped Ether", "WETH");
        regent = new MintableERC20Mock("Regent", "REGENT");
        universalRouter = new MockUniversalRouter(address(regent));
        permit2 = new MockPermit2Allowance();
        usdcWethPoolKey = _poolKey(address(usdc), address(weth));
        wethRegentPoolKey = _poolKey(address(weth), address(regent));
        adapter =
            _adapter(usdcWethPoolKey, wethRegentPoolKey, PoolId.unwrap(wethRegentPoolKey.toId()));
    }

    function testOnlyRouterCanCall() external {
        vm.expectRevert("ONLY_FEE_ROUTER");
        adapter.buyRegent(100e6, 1e18, RECIPIENT);
    }

    function testExactInputSwapSendsRegentToRecipient() external {
        usdc.mint(FEE_ROUTER, 100e6);
        regent.mint(address(universalRouter), 10e18);
        universalRouter.setOutputAmount(10e18);

        vm.prank(FEE_ROUTER);
        usdc.approve(address(adapter), 100e6);

        vm.prank(FEE_ROUTER);
        uint256 bought = adapter.buyRegent(100e6, 9e18, RECIPIENT);

        assertEq(bought, 10e18);
        assertEq(regent.balanceOf(RECIPIENT), 10e18);
        assertEq(usdc.balanceOf(address(adapter)), 100e6);
        assertEq(permit2.lastToken(), address(usdc));
        assertEq(permit2.lastSpender(), address(universalRouter));
        assertEq(permit2.lastAmount(), 100e6);
        assertEq(universalRouter.lastCommands(), hex"10");
        assertEq(universalRouter.lastDeadline(), block.timestamp + adapter.deadlineSeconds());
        assertTrue(universalRouter.lastDeadline() != type(uint256).max);
    }

    function testOutputBelowMinimumReverts() external {
        usdc.mint(FEE_ROUTER, 100e6);
        regent.mint(address(universalRouter), 8e18);
        universalRouter.setOutputAmount(8e18);

        vm.prank(FEE_ROUTER);
        usdc.approve(address(adapter), 100e6);

        vm.prank(FEE_ROUTER);
        vm.expectRevert("REGENT_OUT_LOW");
        adapter.buyRegent(100e6, 9e18, RECIPIENT);
    }

    function testWrongRoutePoolKeyRejected() external {
        PoolKey memory badUsdcWeth = _poolKey(address(usdc), address(regent));

        vm.expectRevert("POOL_NOT_USDC_WETH");
        _adapter(badUsdcWeth, wethRegentPoolKey, PoolId.unwrap(wethRegentPoolKey.toId()));

        PoolKey memory badWethRegent = _poolKey(address(usdc), address(weth));
        vm.expectRevert("POOL_NOT_WETH_REGENT");
        _adapter(usdcWethPoolKey, badWethRegent, PoolId.unwrap(badWethRegent.toId()));

        vm.expectRevert("POOL_ID_MISMATCH");
        _adapter(usdcWethPoolKey, wethRegentPoolKey, bytes32(uint256(1)));
    }

    function testDeadlineIsBounded() external {
        vm.prank(OWNER);
        adapter.setDeadlineSeconds(1800);
        assertEq(adapter.deadlineSeconds(), 1800);

        vm.prank(OWNER);
        vm.expectRevert("DEADLINE_TOO_LONG");
        adapter.setDeadlineSeconds(1801);
    }

    function _adapter(PoolKey memory usdcWeth, PoolKey memory wethRegent, bytes32 poolId)
        internal
        returns (UniswapV4RegentBuybackAdapter)
    {
        return new UniswapV4RegentBuybackAdapter(
            OWNER,
            address(usdc),
            address(weth),
            address(regent),
            FEE_ROUTER,
            address(universalRouter),
            address(permit2),
            usdcWeth,
            wethRegent,
            poolId
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
