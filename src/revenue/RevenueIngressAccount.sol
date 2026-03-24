// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRevenueShareSplitter} from "src/revenue/interfaces/IRevenueShareSplitter.sol";

contract RevenueIngressAccount is Owned {
    using SafeTransferLib for address;

    address public immutable splitter;
    bytes32 public immutable ingressId;

    event Swept(address indexed rewardToken, uint256 amount, bytes32 indexed sourceTag, bytes32 indexed sourceRef);
    event UnsupportedTokenRescued(address indexed token, uint256 amount, address recipient);
    event NativeRescued(uint256 amount, address recipient);

    constructor(address splitter_, bytes32 ingressId_, address owner_) Owned(owner_) {
        require(splitter_ != address(0), "SPLITTER_ZERO");
        splitter = splitter_;
        ingressId = ingressId_;
    }

    receive() external payable {}

    function sweepNative(bytes32 sourceTag) external returns (uint256 amount) {
        amount = _sweepNative(sourceTag);
    }

    function sweepToken(address rewardToken, bytes32 sourceTag) external returns (uint256 amount) {
        amount = _sweepToken(rewardToken, sourceTag);
    }

    function sweepMany(address[] calldata rewardTokens, bytes32 sourceTag) external {
        uint256 length = rewardTokens.length;
        for (uint256 i; i < length; ++i) {
            address rewardToken = rewardTokens[i];
            if (rewardToken == address(0)) {
                if (address(this).balance != 0) {
                    _sweepNative(sourceTag);
                }
            } else if (IERC20SupplyMinimal(rewardToken).balanceOf(address(this)) != 0) {
                _sweepToken(rewardToken, sourceTag);
            }
        }
    }

    function _sweepNative(bytes32 sourceTag) internal returns (uint256 amount) {
        amount = address(this).balance;
        require(amount != 0, "NOTHING_TO_SWEEP");
        bytes32 sourceRef = keccak256(abi.encode(ingressId, sourceTag, address(0), amount));
        IRevenueShareSplitter(splitter).depositNative{value: amount}(sourceTag, sourceRef);
        emit Swept(address(0), amount, sourceTag, sourceRef);
    }

    function _sweepToken(address rewardToken, bytes32 sourceTag) internal returns (uint256 amount) {
        require(rewardToken != address(0), "USE_SWEEP_NATIVE");
        amount = IERC20SupplyMinimal(rewardToken).balanceOf(address(this));
        require(amount != 0, "NOTHING_TO_SWEEP");

        rewardToken.forceApprove(splitter, amount);
        bytes32 sourceRef = keccak256(abi.encode(ingressId, sourceTag, rewardToken, amount));
        IRevenueShareSplitter(splitter).depositToken(rewardToken, amount, sourceTag, sourceRef);
        emit Swept(rewardToken, amount, sourceTag, sourceRef);
    }

    function rescueUnsupportedToken(address token, uint256 amount, address recipient) external onlyOwner {
        require(token != address(0), "USE_RESCUE_NATIVE");
        require(recipient != address(0), "RECIPIENT_ZERO");
        emit UnsupportedTokenRescued(token, amount, recipient);
        token.safeTransfer(recipient, amount);
    }

    function rescueNative(uint256 amount, address recipient) external onlyOwner {
        require(recipient != address(0), "RECIPIENT_ZERO");
        emit NativeRescued(amount, recipient);
        address(0).safeTransfer(recipient, amount);
    }
}
