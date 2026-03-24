// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {RevenueShareSplitter} from "src/revenue/RevenueShareSplitter.sol";
import {SubjectRegistry} from "src/revenue/SubjectRegistry.sol";

contract RevenueShareFactory is Owned {
    SubjectRegistry public immutable subjectRegistry;

    mapping(address => address) public splitterOfStakeToken;
    mapping(bytes32 => address) public splitterOfSubject;

    event SplitterDeployed(
        bytes32 indexed subjectId,
        address indexed stakeToken,
        address indexed splitter,
        address splitterOwner,
        address treasuryRecipient,
        address protocolRecipient,
        string label
    );

    constructor(address owner_, SubjectRegistry subjectRegistry_) Owned(owner_) {
        require(address(subjectRegistry_) != address(0), "REGISTRY_ZERO");
        subjectRegistry = subjectRegistry_;
    }

    function createSubjectSplitter(
        bytes32 subjectId,
        address stakeToken,
        address treasuryRecipient,
        address protocolRecipient,
        address splitterOwner,
        address treasurySafe,
        uint256 emissionChainId,
        address emissionRecipient,
        uint16 protocolSkimBps,
        string calldata label,
        address[] calldata initialRewardTokens
    ) external onlyOwner returns (address splitter) {
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(stakeToken != address(0), "STAKE_TOKEN_ZERO");
        require(splitterOfStakeToken[stakeToken] == address(0), "SPLITTER_EXISTS_FOR_TOKEN");
        require(splitterOfSubject[subjectId] == address(0), "SPLITTER_EXISTS_FOR_SUBJECT");
        require(splitterOwner != address(0), "SPLITTER_OWNER_ZERO");
        require(treasurySafe != address(0), "TREASURY_SAFE_ZERO");

        RevenueShareSplitter deployed = new RevenueShareSplitter(
            stakeToken,
            treasuryRecipient,
            protocolRecipient,
            protocolSkimBps,
            label,
            address(this)
        );

        uint256 rewardTokenCount = initialRewardTokens.length;
        for (uint256 i; i < rewardTokenCount; ++i) {
            deployed.setAllowedRewardToken(initialRewardTokens[i], true);
        }

        deployed.transferOwnership(splitterOwner);

        splitter = address(deployed);
        splitterOfStakeToken[stakeToken] = splitter;
        splitterOfSubject[subjectId] = splitter;

        subjectRegistry.createSubject(subjectId, stakeToken, splitter, treasurySafe, true, label);
        if (emissionChainId != 0 && emissionRecipient != address(0)) {
            subjectRegistry.setEmissionRecipient(subjectId, emissionChainId, emissionRecipient);
        }

        emit SplitterDeployed(
            subjectId,
            stakeToken,
            splitter,
            splitterOwner,
            treasuryRecipient,
            protocolRecipient,
            label
        );
    }
}
