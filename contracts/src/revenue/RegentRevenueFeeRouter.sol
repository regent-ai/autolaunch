// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRegentBuybackAdapter} from "src/revenue/interfaces/IRegentBuybackAdapter.sol";
import {IRegentEmissionVault} from "src/revenue/interfaces/IRegentEmissionVault.sol";
import {IRegentRevenueFeeRouter} from "src/revenue/interfaces/IRegentRevenueFeeRouter.sol";
import {IRegentUsdOracle} from "src/revenue/interfaces/IRegentUsdOracle.sol";
import {ISubjectRegistry} from "src/revenue/interfaces/ISubjectRegistry.sol";

contract RegentRevenueFeeRouter is Owned, IRegentRevenueFeeRouter {
    using SafeTransferLib for address;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant MAX_PROTOCOL_SKIM_BPS = 1000;

    address public immutable override usdc;
    address public immutable override regent;
    address public immutable subjectRegistry;

    IRegentUsdOracle public oracle;
    IRegentEmissionVault public emissionVault;
    IRegentBuybackAdapter public buybackAdapter;

    uint16 public override protocolSkimBps = 1000;
    uint16 public maxBuybackSlippageBps = 500;
    uint256 public maxUsdcPerSettlement = 50_000e6;
    uint256 public totalUsdcSettled;
    uint256 public totalRegentOwed;
    uint256 public totalRegentBought;

    uint256 private _reentrancyGuard = 1;

    event ProtocolSkimBpsSet(uint16 previousBps, uint16 newBps);
    event OracleSet(address indexed oracle);
    event EmissionVaultSet(address indexed emissionVault);
    event BuybackAdapterSet(address indexed buybackAdapter);
    event MaxBuybackSlippageBpsSet(uint16 previousBps, uint16 newBps);
    event MaxUsdcPerSettlementSet(uint256 previousAmount, uint256 newAmount);
    event ProtocolFeeSettled(
        bytes32 indexed subjectId,
        address indexed splitter,
        address indexed subjectTreasury,
        uint256 usdcAmount,
        uint256 regentOwed,
        uint256 regentBought,
        uint256 regentUsdE18,
        bytes32 sourceRef
    );

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    constructor(address owner_, address usdc_, address regent_, address subjectRegistry_)
        Owned(owner_)
    {
        require(usdc_ != address(0), "USDC_ZERO");
        require(regent_ != address(0), "REGENT_ZERO");
        require(subjectRegistry_ != address(0), "SUBJECT_REGISTRY_ZERO");
        usdc = usdc_;
        regent = regent_;
        subjectRegistry = subjectRegistry_;
    }

    function processProtocolFee(
        bytes32 subjectId,
        address subjectTreasury,
        uint256 usdcAmount,
        bytes32 sourceRef
    ) external override nonReentrant returns (uint256 regentOwed, uint256 regentBought) {
        require(usdcAmount != 0, "AMOUNT_ZERO");
        require(usdcAmount <= maxUsdcPerSettlement, "SETTLEMENT_TOO_LARGE");
        require(subjectTreasury != address(0), "TREASURY_ZERO");
        require(address(oracle) != address(0), "ORACLE_ZERO");
        require(address(emissionVault) != address(0), "EMISSION_VAULT_ZERO");
        require(address(buybackAdapter) != address(0), "BUYBACK_ADAPTER_ZERO");

        ISubjectRegistry.SubjectConfig memory cfg =
            ISubjectRegistry(subjectRegistry).getSubject(subjectId);
        require(cfg.splitter == msg.sender, "ONLY_SUBJECT_SPLITTER");
        require(cfg.treasurySafe == subjectTreasury, "TREASURY_MISMATCH");
        require(
            IERC20SupplyMinimal(usdc).balanceOf(address(this)) >= usdcAmount, "USDC_NOT_RECEIVED"
        );

        IRegentUsdOracle.Quote memory quote = oracle.quoteRegentForUsdc(usdcAmount);
        regentOwed = quote.regentAmount;
        require(regentOwed != 0, "REGENT_OWED_ZERO");

        uint256 minRegentOut =
            (regentOwed * (BPS_DENOMINATOR - maxBuybackSlippageBps)) / BPS_DENOMINATOR;
        require(minRegentOut != 0, "MIN_REGENT_OUT_ZERO");

        usdc.forceApprove(address(buybackAdapter), usdcAmount);
        regentBought = buybackAdapter.buyRegent(usdcAmount, minRegentOut, address(emissionVault));
        require(regentBought >= minRegentOut, "REGENT_BUYBACK_LOW");

        emissionVault.emitRegent(subjectTreasury, regentOwed, subjectId, sourceRef);

        totalUsdcSettled += usdcAmount;
        totalRegentOwed += regentOwed;
        totalRegentBought += regentBought;

        emit ProtocolFeeSettled(
            subjectId,
            msg.sender,
            subjectTreasury,
            usdcAmount,
            regentOwed,
            regentBought,
            quote.regentUsdE18,
            sourceRef
        );
    }

    function setProtocolSkimBps(uint16 newBps) external onlyOwner {
        require(newBps <= MAX_PROTOCOL_SKIM_BPS, "PROTOCOL_SKIM_TOO_HIGH");
        uint16 previous = protocolSkimBps;
        protocolSkimBps = newBps;
        emit ProtocolSkimBpsSet(previous, newBps);
    }

    function setOracle(address oracle_) external onlyOwner {
        require(oracle_ != address(0), "ORACLE_ZERO");
        oracle = IRegentUsdOracle(oracle_);
        emit OracleSet(oracle_);
    }

    function setEmissionVault(address emissionVault_) external onlyOwner {
        require(emissionVault_ != address(0), "EMISSION_VAULT_ZERO");
        require(IRegentEmissionVault(emissionVault_).regent() == regent, "VAULT_REGENT_MISMATCH");
        emissionVault = IRegentEmissionVault(emissionVault_);
        emit EmissionVaultSet(emissionVault_);
    }

    function setBuybackAdapter(address buybackAdapter_) external onlyOwner {
        require(buybackAdapter_ != address(0), "BUYBACK_ADAPTER_ZERO");
        require(IRegentBuybackAdapter(buybackAdapter_).usdc() == usdc, "ADAPTER_USDC_MISMATCH");
        require(
            IRegentBuybackAdapter(buybackAdapter_).regent() == regent, "ADAPTER_REGENT_MISMATCH"
        );
        buybackAdapter = IRegentBuybackAdapter(buybackAdapter_);
        emit BuybackAdapterSet(buybackAdapter_);
    }

    function setMaxBuybackSlippageBps(uint16 newBps) external onlyOwner {
        require(newBps <= BPS_DENOMINATOR, "SLIPPAGE_TOO_HIGH");
        uint16 previous = maxBuybackSlippageBps;
        maxBuybackSlippageBps = newBps;
        emit MaxBuybackSlippageBpsSet(previous, newBps);
    }

    function setMaxUsdcPerSettlement(uint256 newAmount) external onlyOwner {
        require(newAmount != 0, "MAX_SETTLEMENT_ZERO");
        uint256 previous = maxUsdcPerSettlement;
        maxUsdcPerSettlement = newAmount;
        emit MaxUsdcPerSettlementSet(previous, newAmount);
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == usdc || token == regent;
    }
}
