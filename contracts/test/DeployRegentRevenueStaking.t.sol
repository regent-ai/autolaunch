// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployRegentRevenueStakingScript} from "scripts/DeployRegentRevenueStaking.s.sol";
import {RegentRevenueStaking} from "src/revenue/RegentRevenueStaking.sol";
import {MintableBurnableERC20Mock} from "test/mocks/MintableBurnableERC20Mock.sol";

contract DeployRegentRevenueStakingScriptTest is Test {
    uint256 internal constant SUPPLY_DENOMINATOR = 100_000_000_000e18;
    address internal constant TREASURY = address(0xBEEF);
    address internal constant OWNER = address(0xA11CE);

    DeployRegentRevenueStakingScript internal script;
    MintableBurnableERC20Mock internal regent;
    MintableBurnableERC20Mock internal usdc;

    function setUp() external {
        script = new DeployRegentRevenueStakingScript();
        regent = new MintableBurnableERC20Mock("Regent", "REGENT", 18);
        usdc = new MintableBurnableERC20Mock("USD Coin", "USDC", 6);
        vm.chainId(8453);
    }

    function testDeployFromEnvRequiresBaseMainnet() external {
        _setRequiredEnv();
        vm.chainId(84_532);

        vm.expectRevert("BASE_MAINNET_ONLY");
        script.loadConfigFromEnv();
    }

    function testDeployFromEnvRequiresFullStakerShare() external {
        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = _defaultScriptConfig();
        cfg.stakerShareBps = 9000;

        vm.expectRevert("STAKER_SHARE_MUST_BE_FULL");
        script.validateConfig(cfg);
    }

    function testDeployFromEnvLoadsCurrentRegentConfig() external {
        _setRequiredEnv();

        DeployRegentRevenueStakingScript.ScriptConfig memory cfg = script.loadConfigFromEnv();

        assertEq(cfg.regentToken, address(regent));
        assertEq(cfg.usdc, address(usdc));
        assertEq(cfg.treasuryRecipient, TREASURY);
        assertEq(cfg.owner, OWNER);
        assertEq(cfg.revenueShareSupplyDenominator, SUPPLY_DENOMINATOR);
        assertEq(cfg.stakerShareBps, 10_000);
    }

    function testDeployCreatesConfiguredStakingContract() external {
        RegentRevenueStaking staking = script.deploy(_defaultScriptConfig());

        assertEq(staking.stakeToken(), address(regent));
        assertEq(staking.usdc(), address(usdc));
        assertEq(staking.treasuryRecipient(), TREASURY);
        assertEq(staking.owner(), OWNER);
        assertEq(staking.revenueShareSupplyDenominator(), SUPPLY_DENOMINATOR);
    }

    function _setRequiredEnv() internal {
        vm.setEnv("BASE_REGENT_TOKEN_ADDRESS", vm.toString(address(regent)));
        vm.setEnv("BASE_USDC_ADDRESS", vm.toString(address(usdc)));
        vm.setEnv("REGENT_REVENUE_TREASURY_ADDRESS", vm.toString(TREASURY));
        vm.setEnv("REGENT_REVENUE_GOVERNANCE_SAFE_ADDRESS", vm.toString(OWNER));
        vm.setEnv("REGENT_REVENUE_SUPPLY_DENOMINATOR", vm.toString(SUPPLY_DENOMINATOR));
        vm.setEnv("REGENT_REVENUE_STAKER_SHARE_BPS", "10000");
    }

    function _defaultScriptConfig()
        internal
        view
        returns (DeployRegentRevenueStakingScript.ScriptConfig memory cfg)
    {
        cfg.regentToken = address(regent);
        cfg.usdc = address(usdc);
        cfg.treasuryRecipient = TREASURY;
        cfg.revenueShareSupplyDenominator = SUPPLY_DENOMINATOR;
        cfg.stakerShareBps = 10_000;
        cfg.owner = OWNER;
    }
}
