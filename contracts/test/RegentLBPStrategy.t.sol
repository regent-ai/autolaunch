// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {AuctionParameters} from "src/cca/interfaces/IContinuousClearingAuction.sol";
import {RegentLBPStrategy} from "src/RegentLBPStrategy.sol";
import {MintableERC20Mock} from "test/mocks/MintableERC20Mock.sol";
import {MockContinuousClearingAuctionFactory} from "test/mocks/MockContinuousClearingAuctionFactory.sol";

contract RegentLBPStrategyTest is Test {
    address internal constant AGENT_TREASURY = address(0x1234);
    address internal constant VESTING_WALLET = address(0x5678);
    address internal constant OPERATOR = address(0x9ABC);
    address internal constant POSITION_RECIPIENT = address(0xDEF0);
    uint128 internal constant AUCTION_AMOUNT = 100e18;
    uint128 internal constant RESERVE_AMOUNT = 50e18;

    MintableERC20Mock internal token;
    MintableERC20Mock internal usdc;
    MockContinuousClearingAuctionFactory internal auctionFactory;
    RegentLBPStrategy internal strategy;

    function setUp() external {
        token = new MintableERC20Mock("Launch Token", "LT");
        usdc = new MintableERC20Mock("USD Coin", "USDC");
        auctionFactory = new MockContinuousClearingAuctionFactory();

        strategy = new RegentLBPStrategy(
            address(token),
            address(usdc),
            address(auctionFactory),
            AuctionParameters({
                currency: address(usdc),
                tokensRecipient: address(0),
                fundsRecipient: address(0),
                startBlock: 1,
                endBlock: 101,
                claimBlock: 101,
                tickSpacing: 1_000,
                validationHook: address(0),
                floorPrice: 1_000,
                requiredCurrencyRaised: 0,
                auctionStepsData: bytes("")
            }),
            address(0xFEE1),
            AGENT_TREASURY,
            VESTING_WALLET,
            OPERATOR,
            POSITION_RECIPIENT,
            address(0xCAFE),
            address(0xBEEF),
            202,
            303,
            5_000,
            6_666_666,
            AUCTION_AMOUNT + RESERVE_AMOUNT,
            AUCTION_AMOUNT,
            RESERVE_AMOUNT,
            type(uint128).max
        );

        token.mint(address(strategy), AUCTION_AMOUNT + RESERVE_AMOUNT);
    }

    function testOnTokensReceivedCreatesStrategyOwnedAuction() external {
        strategy.onTokensReceived();

        assertTrue(strategy.auctionAddress() != address(0));
        assertEq(token.balanceOf(strategy.auctionAddress()), AUCTION_AMOUNT);
        assertEq(token.balanceOf(address(strategy)), RESERVE_AMOUNT);
        assertEq(auctionFactory.lastAmount(), AUCTION_AMOUNT);

        AuctionParameters memory params =
            abi.decode(auctionFactory.lastConfigData(), (AuctionParameters));
        assertEq(params.tokensRecipient, address(strategy));
        assertEq(params.fundsRecipient, address(strategy));
    }

    function testMigrateSplitsRaisedUsdcAndSweepMovesRemainders() external {
        strategy.onTokensReceived();
        usdc.mint(address(strategy), 200e18);

        vm.roll(202);
        vm.prank(OPERATOR);
        strategy.migrate();

        assertEq(usdc.balanceOf(POSITION_RECIPIENT), 100e18);
        assertEq(token.balanceOf(POSITION_RECIPIENT), RESERVE_AMOUNT);
        assertEq(strategy.migratedCurrencyForLP(), 100e18);
        assertEq(strategy.migratedTokenForLP(), RESERVE_AMOUNT);

        token.mint(address(strategy), 12e18);

        vm.roll(303);
        vm.prank(OPERATOR);
        strategy.sweepCurrency();
        vm.prank(OPERATOR);
        strategy.sweepToken();

        assertEq(usdc.balanceOf(AGENT_TREASURY), 100e18);
        assertEq(token.balanceOf(VESTING_WALLET), 12e18);
    }
}
