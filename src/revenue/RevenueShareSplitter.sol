// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";
import {ILaunchFeeVaultMinimal} from "src/revenue/interfaces/ILaunchFeeVaultMinimal.sol";
import {IRevenueShareSplitter} from "src/revenue/interfaces/IRevenueShareSplitter.sol";

contract RevenueShareSplitter is Owned, IRevenueShareSplitter {
    using SafeTransferLib for address;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant ACC_PRECISION = 1e27;

    address public immutable override stakeToken;
    string public label;

    address public override treasuryRecipient;
    address public override protocolRecipient;
    uint16 public protocolSkimBps;

    bool public paused;
    bool public restrictIngress;
    uint256 public override totalStaked;

    address[] private _knownRewardTokens;
    mapping(address => bool) public isKnownRewardToken;
    mapping(address => bool) public allowedRewardToken;
    mapping(address => bool) public allowedIngress;

    mapping(address => uint256) public accRewardPerToken;
    mapping(address => uint256) public treasuryResidual;
    mapping(address => uint256) public protocolReserve;
    mapping(address => uint256) public undistributedDust;

    mapping(address => uint256) public stakedBalance;
    mapping(address => mapping(address => uint256)) public rewardDebt;
    mapping(address => mapping(address => uint256)) public storedClaimable;

    uint256 private _reentrancyGuard = 1;

    event PausedSet(bool paused);
    event RestrictIngressSet(bool restrictIngress);
    event AllowedIngressSet(address indexed account, bool allowed);
    event AllowedRewardTokenSet(address indexed rewardToken, bool allowed);
    event TreasuryRecipientSet(address indexed treasuryRecipient);
    event ProtocolRecipientSet(address indexed protocolRecipient);
    event ProtocolSkimBpsSet(uint16 skimBps);
    event LabelSet(string label);
    event KnownRewardTokenAdded(address indexed rewardToken);
    event StakeUpdated(address indexed account, uint256 newStakeBalance, uint256 totalStaked);
    event RevenueDeposited(
        address indexed rewardToken,
        uint256 amountReceived,
        uint256 protocolAmount,
        uint256 stakerEntitlement,
        uint256 treasuryPortion,
        bytes32 indexed sourceTag,
        bytes32 indexed sourceRef
    );
    event RewardClaimed(address indexed account, address indexed rewardToken, uint256 amount, address recipient);
    event TreasuryResidualWithdrawn(address indexed rewardToken, uint256 amount, address recipient);
    event ProtocolReserveWithdrawn(address indexed rewardToken, uint256 amount, address recipient);
    event DustReassigned(address indexed rewardToken, uint256 amount, address recipient);

    constructor(
        address stakeToken_,
        address treasuryRecipient_,
        address protocolRecipient_,
        uint16 protocolSkimBps_,
        string memory label_,
        address owner_
    ) Owned(owner_) {
        require(stakeToken_ != address(0), "STAKE_TOKEN_ZERO");
        require(treasuryRecipient_ != address(0), "TREASURY_ZERO");
        require(protocolRecipient_ != address(0), "PROTOCOL_ZERO");
        require(protocolSkimBps_ <= BPS_DENOMINATOR, "SKIM_BPS_INVALID");

        stakeToken = stakeToken_;
        treasuryRecipient = treasuryRecipient_;
        protocolRecipient = protocolRecipient_;
        protocolSkimBps = protocolSkimBps_;
        label = label_;
    }

    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    modifier nonReentrant() {
        require(_reentrancyGuard == 1, "REENTRANT");
        _reentrancyGuard = 2;
        _;
        _reentrancyGuard = 1;
    }

    receive() external payable {}

    function knownRewardTokenCount() external view override returns (uint256) {
        return _knownRewardTokens.length;
    }

    function knownRewardTokenAt(uint256 index) external view override returns (address) {
        return _knownRewardTokens[index];
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function setRestrictIngress(bool restrictIngress_) external onlyOwner {
        restrictIngress = restrictIngress_;
        emit RestrictIngressSet(restrictIngress_);
    }

    function setAllowedIngress(address account, bool allowed) external onlyOwner {
        require(account != address(0), "ACCOUNT_ZERO");
        allowedIngress[account] = allowed;
        emit AllowedIngressSet(account, allowed);
    }

    function setAllowedRewardToken(address rewardToken, bool allowed) external onlyOwner {
        allowedRewardToken[rewardToken] = allowed;
        emit AllowedRewardTokenSet(rewardToken, allowed);
    }

    function setTreasuryRecipient(address treasuryRecipient_) external onlyOwner {
        require(treasuryRecipient_ != address(0), "TREASURY_ZERO");
        treasuryRecipient = treasuryRecipient_;
        emit TreasuryRecipientSet(treasuryRecipient_);
    }

    function setProtocolRecipient(address protocolRecipient_) external onlyOwner {
        require(protocolRecipient_ != address(0), "PROTOCOL_ZERO");
        protocolRecipient = protocolRecipient_;
        emit ProtocolRecipientSet(protocolRecipient_);
    }

    function setProtocolSkimBps(uint16 protocolSkimBps_) external onlyOwner {
        require(protocolSkimBps_ <= BPS_DENOMINATOR, "SKIM_BPS_INVALID");
        protocolSkimBps = protocolSkimBps_;
        emit ProtocolSkimBpsSet(protocolSkimBps_);
    }

    function setLabel(string calldata label_) external onlyOwner {
        label = label_;
        emit LabelSet(label_);
    }

    function stake(uint256 amount, address receiver) external whenNotPaused nonReentrant {
        require(amount != 0, "AMOUNT_ZERO");
        require(receiver != address(0), "RECEIVER_ZERO");

        _syncAllKnown(receiver);

        stakedBalance[receiver] += amount;
        totalStaked += amount;

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit StakeUpdated(receiver, stakedBalance[receiver], totalStaked);
    }

    function unstake(uint256 amount, address recipient) external whenNotPaused nonReentrant {
        require(amount != 0, "AMOUNT_ZERO");
        require(recipient != address(0), "RECIPIENT_ZERO");

        _syncAllKnown(msg.sender);

        uint256 currentStake = stakedBalance[msg.sender];
        require(currentStake >= amount, "STAKE_BALANCE_LOW");

        unchecked {
            stakedBalance[msg.sender] = currentStake - amount;
            totalStaked -= amount;
        }

        emit StakeUpdated(msg.sender, stakedBalance[msg.sender], totalStaked);
        stakeToken.safeTransfer(recipient, amount);
    }

    function depositToken(address rewardToken, uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 received)
    {
        require(rewardToken != address(0), "USE_NATIVE_DEPOSIT");
        require(amount != 0, "AMOUNT_ZERO");
        _checkIngress(msg.sender);
        _checkRewardToken(rewardToken);

        uint256 beforeBalance = IERC20SupplyMinimal(rewardToken).balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(rewardToken).balanceOf(address(this));
        received = afterBalance - beforeBalance;
        _recordRevenue(rewardToken, received, sourceTag, sourceRef);
    }

    function depositNative(bytes32 sourceTag, bytes32 sourceRef)
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (uint256 received)
    {
        _checkIngress(msg.sender);
        _checkRewardToken(address(0));
        received = msg.value;
        _recordRevenue(address(0), received, sourceTag, sourceRef);
    }

    function pullTreasuryShareFromLaunchVault(
        address vault,
        bytes32 poolId,
        address rewardToken,
        uint256 amount,
        bytes32 sourceRef
    ) external whenNotPaused nonReentrant returns (uint256 received) {
        require(vault != address(0), "VAULT_ZERO");
        require(amount != 0, "AMOUNT_ZERO");
        _checkRewardToken(rewardToken);

        uint256 beforeBalance = _balanceOf(rewardToken, address(this));
        ILaunchFeeVaultMinimal(vault).withdrawTreasury(poolId, rewardToken, amount, address(this));
        uint256 afterBalance = _balanceOf(rewardToken, address(this));
        received = afterBalance - beforeBalance;
        _recordRevenue(rewardToken, received, bytes32("launch_treasury"), sourceRef);
    }

    function pullRegentShareFromLaunchVault(
        address vault,
        bytes32 poolId,
        address rewardToken,
        uint256 amount,
        bytes32 sourceRef
    ) external whenNotPaused nonReentrant returns (uint256 received) {
        require(vault != address(0), "VAULT_ZERO");
        require(amount != 0, "AMOUNT_ZERO");
        _checkRewardToken(rewardToken);

        uint256 beforeBalance = _balanceOf(rewardToken, address(this));
        ILaunchFeeVaultMinimal(vault).withdrawRegentShare(poolId, rewardToken, amount, address(this));
        uint256 afterBalance = _balanceOf(rewardToken, address(this));
        received = afterBalance - beforeBalance;
        _recordRevenue(rewardToken, received, bytes32("launch_regent"), sourceRef);
    }

    function sync(address account, address[] calldata rewardTokens)
        external
        whenNotPaused
        nonReentrant
    {
        require(account != address(0), "ACCOUNT_ZERO");
        uint256 length = rewardTokens.length;
        for (uint256 i; i < length; ++i) {
            _syncToken(account, rewardTokens[i]);
        }
    }

    function claim(address[] calldata rewardTokens, address recipient)
        external
        whenNotPaused
        nonReentrant
        returns (uint256[] memory amounts)
    {
        require(recipient != address(0), "RECIPIENT_ZERO");
        uint256 length = rewardTokens.length;
        amounts = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            amounts[i] = _claimToken(msg.sender, rewardTokens[i], 0, recipient, false);
        }
    }

    function claimWithMinimums(
        address[] calldata rewardTokens,
        uint256[] calldata minimums,
        address recipient
    ) external whenNotPaused nonReentrant returns (uint256[] memory amounts) {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(rewardTokens.length == minimums.length, "LENGTH_MISMATCH");

        uint256 length = rewardTokens.length;
        amounts = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            amounts[i] = _claimToken(msg.sender, rewardTokens[i], minimums[i], recipient, true);
        }
    }

    function claimAllKnown(uint256 cursor, uint256 limit, uint256 minAmount, address recipient)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 nextCursor, uint256 claimedCount)
    {
        require(recipient != address(0), "RECIPIENT_ZERO");

        uint256 length = _knownRewardTokens.length;
        if (cursor >= length || limit == 0) {
            return (cursor, 0);
        }

        uint256 end = cursor + limit;
        if (end > length) end = length;

        for (uint256 i = cursor; i < end; ++i) {
            uint256 amount = _claimToken(msg.sender, _knownRewardTokens[i], minAmount, recipient, true);
            if (amount != 0) {
                ++claimedCount;
            }
        }

        nextCursor = end;
    }

    function withdrawTreasuryResidual(address rewardToken, uint256 amount, address recipient)
        external
        whenNotPaused
        nonReentrant
    {
        require(msg.sender == treasuryRecipient || msg.sender == owner, "ONLY_TREASURY");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(treasuryResidual[rewardToken] >= amount, "TREASURY_BALANCE_LOW");

        treasuryResidual[rewardToken] -= amount;
        emit TreasuryResidualWithdrawn(rewardToken, amount, recipient);
        rewardToken.safeTransfer(recipient, amount);
    }

    function withdrawProtocolReserve(address rewardToken, uint256 amount, address recipient)
        external
        whenNotPaused
        nonReentrant
    {
        require(msg.sender == protocolRecipient || msg.sender == owner, "ONLY_PROTOCOL");
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(protocolReserve[rewardToken] >= amount, "PROTOCOL_BALANCE_LOW");

        protocolReserve[rewardToken] -= amount;
        emit ProtocolReserveWithdrawn(rewardToken, amount, recipient);
        rewardToken.safeTransfer(recipient, amount);
    }

    function reassignUndistributedDustToTreasury(address rewardToken, uint256 amount)
        external
        onlyOwner
        nonReentrant
    {
        require(undistributedDust[rewardToken] >= amount, "DUST_BALANCE_LOW");
        undistributedDust[rewardToken] -= amount;
        treasuryResidual[rewardToken] += amount;
        emit DustReassigned(rewardToken, amount, treasuryRecipient);
    }

    function previewClaimable(address account, address rewardToken)
        public
        view
        override
        returns (uint256)
    {
        uint256 claimable = storedClaimable[account][rewardToken];
        uint256 currentAcc = accRewardPerToken[rewardToken];
        uint256 priorAcc = rewardDebt[account][rewardToken];
        if (currentAcc <= priorAcc) {
            return claimable;
        }

        uint256 stakeBal = stakedBalance[account];
        if (stakeBal == 0) {
            return claimable;
        }

        uint256 delta = currentAcc - priorAcc;
        return claimable + FullMath.mulDiv(stakeBal, delta, ACC_PRECISION);
    }

    function _claimToken(
        address account,
        address rewardToken,
        uint256 minimum,
        address recipient,
        bool skipBelowMinimum
    ) internal returns (uint256 amount) {
        _syncToken(account, rewardToken);

        amount = storedClaimable[account][rewardToken];
        if (amount == 0) {
            return 0;
        }
        if (skipBelowMinimum && amount < minimum) {
            return 0;
        }
        require(amount >= minimum, "CLAIM_BELOW_MINIMUM");

        storedClaimable[account][rewardToken] = 0;
        emit RewardClaimed(account, rewardToken, amount, recipient);
        rewardToken.safeTransfer(recipient, amount);
    }

    function _syncAllKnown(address account) internal {
        uint256 length = _knownRewardTokens.length;
        for (uint256 i; i < length; ++i) {
            _syncToken(account, _knownRewardTokens[i]);
        }
    }

    function _syncToken(address account, address rewardToken) internal {
        uint256 currentAcc = accRewardPerToken[rewardToken];
        uint256 priorAcc = rewardDebt[account][rewardToken];
        if (currentAcc == priorAcc) {
            return;
        }

        uint256 stakeBal = stakedBalance[account];
        if (stakeBal != 0) {
            storedClaimable[account][rewardToken] +=
                FullMath.mulDiv(stakeBal, currentAcc - priorAcc, ACC_PRECISION);
        }
        rewardDebt[account][rewardToken] = currentAcc;
    }

    function _recordRevenue(address rewardToken, uint256 received, bytes32 sourceTag, bytes32 sourceRef)
        internal
    {
        require(received != 0, "NOTHING_RECEIVED");

        uint256 supply = IERC20SupplyMinimal(stakeToken).totalSupply();
        require(supply != 0, "SUPPLY_ZERO");

        _addKnownRewardToken(rewardToken);

        uint256 protocolAmount = protocolSkimBps == 0
            ? 0
            : FullMath.mulDiv(received, protocolSkimBps, BPS_DENOMINATOR);
        uint256 net = received - protocolAmount;

        uint256 deltaAcc = net == 0 ? 0 : FullMath.mulDiv(net, ACC_PRECISION, supply);
        if (deltaAcc != 0) {
            accRewardPerToken[rewardToken] += deltaAcc;
        }

        uint256 stakerEntitlement = net == 0 || totalStaked == 0
            ? 0
            : FullMath.mulDiv(net, totalStaked, supply);
        uint256 treasuryPortion = net - stakerEntitlement;
        uint256 creditedByAccumulator = deltaAcc == 0 || totalStaked == 0
            ? 0
            : FullMath.mulDiv(deltaAcc, totalStaked, ACC_PRECISION);

        treasuryResidual[rewardToken] += treasuryPortion;
        protocolReserve[rewardToken] += protocolAmount;
        if (stakerEntitlement > creditedByAccumulator) {
            undistributedDust[rewardToken] += stakerEntitlement - creditedByAccumulator;
        }

        emit RevenueDeposited(
            rewardToken,
            received,
            protocolAmount,
            stakerEntitlement,
            treasuryPortion,
            sourceTag,
            sourceRef
        );
    }

    function _checkIngress(address account) internal view {
        if (!restrictIngress) {
            return;
        }
        require(allowedIngress[account], "INGRESS_NOT_ALLOWED");
    }

    function _checkRewardToken(address rewardToken) internal view {
        require(allowedRewardToken[rewardToken], "REWARD_TOKEN_NOT_ALLOWED");
    }

    function _addKnownRewardToken(address rewardToken) internal {
        if (isKnownRewardToken[rewardToken]) {
            return;
        }
        isKnownRewardToken[rewardToken] = true;
        _knownRewardTokens.push(rewardToken);
        emit KnownRewardTokenAdded(rewardToken);
    }

    function _balanceOf(address rewardToken, address account) internal view returns (uint256) {
        if (rewardToken == address(0)) {
            return account.balance;
        }
        return IERC20SupplyMinimal(rewardToken).balanceOf(account);
    }
}
