// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IRegentBuybackAdapter} from "src/revenue/interfaces/IRegentBuybackAdapter.sol";
import {IRegentUsdOracle} from "src/revenue/interfaces/IRegentUsdOracle.sol";
import {RegentEmissionVault} from "src/revenue/RegentEmissionVault.sol";
import {RegentRevenueFeeRouter} from "src/revenue/RegentRevenueFeeRouter.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";

contract MockRegentUsdOracle is IRegentUsdOracle {
    uint256 public regentAmount;
    uint256 public regentUsdE18;

    constructor(uint256 regentAmount_, uint256 regentUsdE18_) {
        regentAmount = regentAmount_;
        regentUsdE18 = regentUsdE18_;
    }

    function setQuote(uint256 regentAmount_, uint256 regentUsdE18_) external {
        regentAmount = regentAmount_;
        regentUsdE18 = regentUsdE18_;
    }

    function quoteRegentForUsdc(uint256 usdcAmount) external view returns (Quote memory) {
        return Quote({
            usdcAmount: usdcAmount,
            regentAmount: regentAmount,
            regentUsdE18: regentUsdE18,
            ethUsdE18: 1e18,
            regentWethTick: 0,
            regentWethLiquidity: 1
        });
    }
}

contract MockRegentBuybackAdapter is IRegentBuybackAdapter {
    using SafeTransferLib for address;

    address public immutable override usdc;
    address public immutable override regent;
    uint256 public outputAmount;
    uint256 public lastUsdcAmount;
    uint256 public lastMinRegentOut;
    address public lastRecipient;

    constructor(address usdc_, address regent_) {
        usdc = usdc_;
        regent = regent_;
    }

    function setOutputAmount(uint256 outputAmount_) external {
        outputAmount = outputAmount_;
    }

    function buyRegent(uint256 usdcAmount, uint256 minRegentOut, address recipient)
        external
        returns (uint256 regentBought)
    {
        lastUsdcAmount = usdcAmount;
        lastMinRegentOut = minRegentOut;
        lastRecipient = recipient;
        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        regentBought = outputAmount;
        if (regentBought > 0) {
            regent.safeTransfer(recipient, regentBought);
        }
    }
}

    contract RegentRevenueFeeRouterTest is Test {
        bytes32 internal constant SUBJECT_ID = keccak256("subject");
        address internal constant OWNER = address(0xA11CE);
        address internal constant TREASURY = address(0x1111);
        address internal constant OTHER_TREASURY = address(0x2222);
        uint256 internal constant USDC_FEE = 100e6;
        uint256 internal constant REGENT_OWED = 100e18;

        MintableERC20Mock internal usdc;
        MintableERC20Mock internal regent;
        SubjectRegistry internal subjectRegistry;
        RegentRevenueFeeRouter internal router;
        RegentEmissionVault internal vault;
        MockRegentUsdOracle internal oracle;
        MockRegentBuybackAdapter internal buybackAdapter;

        function setUp() external {
            usdc = new MintableERC20Mock("USD Coin", "USDC");
            regent = new MintableERC20Mock("Regent", "REGENT");
            subjectRegistry = new SubjectRegistry(OWNER);
            router = new RegentRevenueFeeRouter(
                OWNER, address(usdc), address(regent), address(subjectRegistry)
            );
            vault = new RegentEmissionVault(address(regent), OWNER);
            oracle = new MockRegentUsdOracle(REGENT_OWED, 1e18);
            buybackAdapter = new MockRegentBuybackAdapter(address(usdc), address(regent));

            vm.startPrank(OWNER);
            subjectRegistry.createSubject(
                SUBJECT_ID, address(0xBEEF), address(this), TREASURY, true, "Subject"
            );
            vault.setRouter(address(router));
            router.setOracle(address(oracle));
            router.setEmissionVault(address(vault));
            router.setBuybackAdapter(address(buybackAdapter));
            vm.stopPrank();
        }

        function testRouterAcceptsFeeOnlyFromRegisteredSubjectSplitter() external {
            usdc.mint(address(router), USDC_FEE);

            vm.prank(address(0xDEAD));
            vm.expectRevert("ONLY_SUBJECT_SPLITTER");
            router.processProtocolFee(SUBJECT_ID, TREASURY, USDC_FEE, bytes32("source"));
        }

        function testRouterRejectsTreasuryMismatch() external {
            usdc.mint(address(router), USDC_FEE);

            vm.expectRevert("TREASURY_MISMATCH");
            router.processProtocolFee(SUBJECT_ID, OTHER_TREASURY, USDC_FEE, bytes32("source"));
        }

        function testRouterQuotesBuysAndTransfersEmissionToTreasury() external {
            usdc.mint(address(router), USDC_FEE);
            regent.mint(address(buybackAdapter), REGENT_OWED);
            buybackAdapter.setOutputAmount(REGENT_OWED);

            (uint256 owed, uint256 bought) =
                router.processProtocolFee(SUBJECT_ID, TREASURY, USDC_FEE, bytes32("source"));

            assertEq(owed, REGENT_OWED);
            assertEq(bought, REGENT_OWED);
            assertEq(regent.balanceOf(TREASURY), REGENT_OWED);
            assertEq(regent.balanceOf(address(vault)), 0);
            assertEq(usdc.balanceOf(address(buybackAdapter)), USDC_FEE);
            assertEq(buybackAdapter.lastMinRegentOut(), 95e18);
            assertEq(router.totalUsdcSettled(), USDC_FEE);
            assertEq(router.totalRegentOwed(), REGENT_OWED);
            assertEq(router.totalRegentBought(), REGENT_OWED);
        }

        function testBoughtBelowOwedSucceedsWhenVaultInventoryCoversDifference() external {
            usdc.mint(address(router), USDC_FEE);
            regent.mint(address(buybackAdapter), 95e18);
            regent.mint(address(vault), 5e18);
            buybackAdapter.setOutputAmount(95e18);

            (uint256 owed, uint256 bought) =
                router.processProtocolFee(SUBJECT_ID, TREASURY, USDC_FEE, bytes32("source"));

            assertEq(owed, REGENT_OWED);
            assertEq(bought, 95e18);
            assertEq(regent.balanceOf(TREASURY), REGENT_OWED);
            assertEq(regent.balanceOf(address(vault)), 0);
        }

        function testInsufficientVaultInventoryReverts() external {
            usdc.mint(address(router), USDC_FEE);
            regent.mint(address(buybackAdapter), 1e18);
            buybackAdapter.setOutputAmount(1e18);

            vm.prank(OWNER);
            router.setMaxBuybackSlippageBps(9900);

            vm.expectRevert("REGENT_INVENTORY_LOW");
            router.processProtocolFee(SUBJECT_ID, TREASURY, USDC_FEE, bytes32("source"));
        }

        function testSlippageLowOutputReverts() external {
            usdc.mint(address(router), USDC_FEE);
            regent.mint(address(buybackAdapter), 94e18);
            buybackAdapter.setOutputAmount(94e18);

            vm.expectRevert("REGENT_BUYBACK_LOW");
            router.processProtocolFee(SUBJECT_ID, TREASURY, USDC_FEE, bytes32("source"));
        }

        function testSettlementLargerThanMaxReverts() external {
            uint256 tooLarge = router.maxUsdcPerSettlement() + 1;
            usdc.mint(address(router), tooLarge);

            vm.expectRevert("SETTLEMENT_TOO_LARGE");
            router.processProtocolFee(SUBJECT_ID, TREASURY, tooLarge, bytes32("source"));
        }

        function testProtocolFeeBpsCannotExceedCapButCanReturnToCap() external {
            vm.startPrank(OWNER);
            router.setProtocolSkimBps(500);
            assertEq(router.protocolSkimBps(), 500);
            router.setProtocolSkimBps(1000);
            assertEq(router.protocolSkimBps(), 1000);

            vm.expectRevert("PROTOCOL_SKIM_TOO_HIGH");
            router.setProtocolSkimBps(1001);
            vm.stopPrank();
        }
    }
