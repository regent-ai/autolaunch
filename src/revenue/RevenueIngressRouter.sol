// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {ISubjectRegistry} from "src/revenue/interfaces/ISubjectRegistry.sol";
import {IRevenueShareSplitter} from "src/revenue/interfaces/IRevenueShareSplitter.sol";

contract RevenueIngressRouter is Owned {
    using SafeTransferLib for address;

    ISubjectRegistry public immutable subjectRegistry;
    bool public paused;

    event PausedSet(bool paused);
    event RoutedToken(
        bytes32 indexed subjectId,
        address indexed rewardToken,
        address indexed payer,
        uint256 amount,
        bytes32 sourceTag,
        bytes32 sourceRef,
        address splitter
    );
    event RoutedNative(
        bytes32 indexed subjectId,
        address indexed payer,
        uint256 amount,
        bytes32 sourceTag,
        bytes32 sourceRef,
        address splitter
    );

    constructor(address owner_, ISubjectRegistry subjectRegistry_) Owned(owner_) {
        require(address(subjectRegistry_) != address(0), "REGISTRY_ZERO");
        subjectRegistry = subjectRegistry_;
    }

    modifier whenNotPaused() {
        require(!paused, "PAUSED");
        _;
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function depositToken(
        bytes32 subjectId,
        address rewardToken,
        uint256 amount,
        bytes32 sourceTag,
        bytes32 sourceRef
    ) external whenNotPaused returns (uint256 received) {
        require(rewardToken != address(0), "USE_NATIVE_DEPOSIT");
        require(amount != 0, "AMOUNT_ZERO");
        address splitter = subjectRegistry.splitterOfSubject(subjectId);
        require(splitter != address(0), "SPLITTER_NOT_FOUND");

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardToken.forceApprove(splitter, amount);
        received = IRevenueShareSplitter(splitter).depositToken(rewardToken, amount, sourceTag, sourceRef);

        emit RoutedToken(subjectId, rewardToken, msg.sender, received, sourceTag, sourceRef, splitter);
    }

    function depositNative(bytes32 subjectId, bytes32 sourceTag, bytes32 sourceRef)
        external
        payable
        whenNotPaused
        returns (uint256 received)
    {
        require(msg.value != 0, "AMOUNT_ZERO");
        address splitter = subjectRegistry.splitterOfSubject(subjectId);
        require(splitter != address(0), "SPLITTER_NOT_FOUND");

        received = IRevenueShareSplitter(splitter).depositNative{value: msg.value}(sourceTag, sourceRef);
        emit RoutedNative(subjectId, msg.sender, received, sourceTag, sourceRef, splitter);
    }
}
