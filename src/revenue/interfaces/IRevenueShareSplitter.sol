// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IRevenueShareSplitter {
    function stakeToken() external view returns (address);
    function treasuryRecipient() external view returns (address);
    function protocolRecipient() external view returns (address);
    function totalStaked() external view returns (uint256);

    function knownRewardTokenCount() external view returns (uint256);
    function knownRewardTokenAt(uint256 index) external view returns (address);
    function previewClaimable(address account, address rewardToken) external view returns (uint256);

    function depositToken(address rewardToken, uint256 amount, bytes32 sourceTag, bytes32 sourceRef)
        external
        returns (uint256 received);

    function depositNative(bytes32 sourceTag, bytes32 sourceRef)
        external
        payable
        returns (uint256 received);
}
