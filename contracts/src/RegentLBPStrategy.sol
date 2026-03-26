// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AuctionParameters} from "src/cca/interfaces/IContinuousClearingAuction.sol";
import {IContinuousClearingAuctionFactory} from "src/cca/interfaces/IContinuousClearingAuctionFactory.sol";
import {IDistributionContract} from "src/cca/interfaces/external/IDistributionContract.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";

contract RegentLBPStrategy is IDistributionContract {
    using SafeTransferLib for address;

    uint16 internal constant BPS_DENOMINATOR = 10_000;

    address public immutable token;
    address public immutable usdc;
    address public immutable auctionInitializerFactory;
    address public immutable officialPoolHook;
    address public immutable agentTreasurySafe;
    address public immutable vestingWallet;
    address public immutable operator;
    address public immutable positionRecipient;
    address public immutable positionManager;
    address public immutable poolManager;

    uint64 public immutable migrationBlock;
    uint64 public immutable sweepBlock;
    uint16 public immutable lpCurrencyBps;
    uint24 public immutable tokenSplitToAuctionMps;
    uint128 public immutable totalStrategySupply;
    uint128 public immutable auctionTokenAmount;
    uint128 public immutable reserveTokenAmount;
    uint128 public immutable maxCurrencyAmountForLP;

    AuctionParameters public auctionParameters;
    address public auctionAddress;
    uint128 public migratedCurrencyForLP;
    uint128 public migratedTokenForLP;
    bool public migrated;

    event AuctionCreated(address indexed auction, uint128 auctionTokenAmount);
    event Migrated(
        address indexed positionRecipient,
        uint128 currencyUsedForLP,
        uint128 tokenUsedForLP
    );
    event TokensSweptToVesting(address indexed vestingWallet, uint256 amount);
    event CurrencySweptToTreasury(address indexed treasury, uint256 amount);

    constructor(
        address token_,
        address usdc_,
        address auctionInitializerFactory_,
        AuctionParameters memory auctionParameters_,
        address officialPoolHook_,
        address agentTreasurySafe_,
        address vestingWallet_,
        address operator_,
        address positionRecipient_,
        address positionManager_,
        address poolManager_,
        uint64 migrationBlock_,
        uint64 sweepBlock_,
        uint16 lpCurrencyBps_,
        uint24 tokenSplitToAuctionMps_,
        uint128 totalStrategySupply_,
        uint128 auctionTokenAmount_,
        uint128 reserveTokenAmount_,
        uint128 maxCurrencyAmountForLP_
    ) {
        require(token_ != address(0), "TOKEN_ZERO");
        require(usdc_ != address(0), "USDC_ZERO");
        require(auctionInitializerFactory_ != address(0), "AUCTION_FACTORY_ZERO");
        require(agentTreasurySafe_ != address(0), "TREASURY_ZERO");
        require(vestingWallet_ != address(0), "VESTING_ZERO");
        require(operator_ != address(0), "OPERATOR_ZERO");
        require(positionRecipient_ != address(0), "POSITION_RECIPIENT_ZERO");
        require(migrationBlock_ > auctionParameters_.endBlock, "MIGRATION_BEFORE_END");
        require(sweepBlock_ > migrationBlock_, "SWEEP_BEFORE_MIGRATION");
        require(lpCurrencyBps_ <= BPS_DENOMINATOR, "LP_BPS_INVALID");
        require(totalStrategySupply_ != 0, "SUPPLY_ZERO");
        require(
            uint256(auctionTokenAmount_) + uint256(reserveTokenAmount_) == totalStrategySupply_,
            "SUPPLY_SPLIT_INVALID"
        );
        require(auctionTokenAmount_ != 0, "AUCTION_SUPPLY_ZERO");

        token = token_;
        usdc = usdc_;
        auctionInitializerFactory = auctionInitializerFactory_;
        officialPoolHook = officialPoolHook_;
        agentTreasurySafe = agentTreasurySafe_;
        vestingWallet = vestingWallet_;
        operator = operator_;
        positionRecipient = positionRecipient_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        migrationBlock = migrationBlock_;
        sweepBlock = sweepBlock_;
        lpCurrencyBps = lpCurrencyBps_;
        tokenSplitToAuctionMps = tokenSplitToAuctionMps_;
        totalStrategySupply = totalStrategySupply_;
        auctionTokenAmount = auctionTokenAmount_;
        reserveTokenAmount = reserveTokenAmount_;
        maxCurrencyAmountForLP = maxCurrencyAmountForLP_;
        auctionParameters = auctionParameters_;
    }

    function onTokensReceived() external {
        require(auctionAddress == address(0), "AUCTION_ALREADY_CREATED");
        require(
            IERC20SupplyMinimal(token).balanceOf(address(this)) >= totalStrategySupply,
            "STRATEGY_BALANCE_LOW"
        );

        AuctionParameters memory params = auctionParameters;
        params.tokensRecipient = address(this);
        params.fundsRecipient = address(this);

        IDistributionContract auction = IContinuousClearingAuctionFactory(auctionInitializerFactory)
            .initializeDistribution(token, auctionTokenAmount, abi.encode(params), bytes32(0));

        auctionAddress = address(auction);
        token.safeTransfer(auctionAddress, auctionTokenAmount);
        auction.onTokensReceived();

        emit AuctionCreated(auctionAddress, auctionTokenAmount);
    }

    function migrate() external {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= migrationBlock, "MIGRATION_NOT_ALLOWED");
        require(!migrated, "ALREADY_MIGRATED");

        uint256 currencyBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        require(currencyBalance != 0, "NO_CURRENCY_RAISED");

        uint256 cappedCurrency = currencyBalance;
        if (cappedCurrency > maxCurrencyAmountForLP) {
            cappedCurrency = maxCurrencyAmountForLP;
        }

        uint256 currencyForLP = (cappedCurrency * lpCurrencyBps) / BPS_DENOMINATOR;
        require(currencyForLP != 0, "LP_CURRENCY_ZERO");

        uint256 tokenBalance = IERC20SupplyMinimal(token).balanceOf(address(this));
        uint256 tokenForLP = tokenBalance > reserveTokenAmount ? reserveTokenAmount : tokenBalance;
        require(tokenForLP != 0, "LP_TOKEN_ZERO");

        migrated = true;
        migratedCurrencyForLP = uint128(currencyForLP);
        migratedTokenForLP = uint128(tokenForLP);

        usdc.safeTransfer(positionRecipient, currencyForLP);
        token.safeTransfer(positionRecipient, tokenForLP);

        emit Migrated(positionRecipient, uint128(currencyForLP), uint128(tokenForLP));
    }

    function sweepToken() external {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= sweepBlock, "SWEEP_NOT_ALLOWED");

        uint256 tokenBalance = IERC20SupplyMinimal(token).balanceOf(address(this));
        require(tokenBalance != 0, "NOTHING_TO_SWEEP");

        token.safeTransfer(vestingWallet, tokenBalance);

        emit TokensSweptToVesting(vestingWallet, tokenBalance);
    }

    function sweepCurrency() external {
        require(msg.sender == operator, "NOT_OPERATOR");
        require(block.number >= sweepBlock, "SWEEP_NOT_ALLOWED");

        uint256 currencyBalance = IERC20SupplyMinimal(usdc).balanceOf(address(this));
        require(currencyBalance != 0, "NOTHING_TO_SWEEP");

        usdc.safeTransfer(agentTreasurySafe, currencyBalance);

        emit CurrencySweptToTreasury(agentTreasurySafe, currencyBalance);
    }
}
