// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {MerkleProofLib} from "src/revenue/libraries/MerkleProofLib.sol";

contract RegentEmissionsDistributorV2 is Owned {
    using SafeTransferLib for address;

    bytes32 public constant EPOCH_PUBLISHER_ROLE = keccak256("EPOCH_PUBLISHER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant EPOCH_LENGTH = 3 days;

    struct EpochEmission {
        bytes32 root;
        bytes32 manifestHash;
        uint128 totalRevenueUsdc;
        uint128 emissionAmount;
        bool published;
    }

    address public immutable regent;
    uint256 public immutable genesisTs;

    bool public paused;
    mapping(bytes32 => mapping(address => bool)) private roles;
    mapping(uint32 => EpochEmission) public epochs;
    mapping(uint32 => mapping(uint256 => uint256)) private claimedBitMap;
    mapping(uint32 => mapping(bytes32 => bool)) public subjectClaimed;

    event RoleSet(bytes32 indexed role, address indexed account, bool enabled);
    event PausedSet(bool paused);
    event EpochPublished(
        uint32 indexed epoch,
        uint256 totalRevenueUsdc,
        uint256 emissionAmount,
        bytes32 root,
        bytes32 manifestHash
    );
    event Claimed(
        uint32 indexed epoch,
        uint256 indexed index,
        bytes32 indexed subjectId,
        address recipient,
        uint256 amount
    );

    constructor(address regent_, uint256 genesisTs_, address owner_) Owned(owner_) {
        require(regent_ != address(0), "REGENT_ZERO");
        require(genesisTs_ != 0, "GENESIS_ZERO");

        regent = regent_;
        genesisTs = genesisTs_;

        _setRole(EPOCH_PUBLISHER_ROLE, owner_, true);
        _setRole(PAUSER_ROLE, owner_, true);
    }

    modifier onlyRole(bytes32 role) {
        require(roles[role][msg.sender], "MISSING_ROLE");
        _;
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

    uint256 private _reentrancyGuard = 1;

    function currentEpoch() public view returns (uint32) {
        if (block.timestamp <= genesisTs) {
            return 1;
        }
        return uint32((block.timestamp - genesisTs) / EPOCH_LENGTH) + 1;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return roles[role][account];
    }

    function setRole(bytes32 role, address account, bool enabled) external onlyOwner {
        _setRole(role, account, enabled);
    }

    function setPaused(bool paused_) external onlyRole(PAUSER_ROLE) {
        paused = paused_;
        emit PausedSet(paused_);
    }

    function isClaimed(uint32 epoch, uint256 index) external view returns (bool) {
        return _isClaimed(epoch, index);
    }

    function publishEpochEmission(
        uint32 epoch,
        uint256 totalRevenueUsdc,
        uint256 emissionAmount,
        bytes32 root,
        bytes32 manifestHash
    ) external onlyRole(EPOCH_PUBLISHER_ROLE) whenNotPaused nonReentrant {
        require(epoch < currentEpoch(), "EPOCH_NOT_CLOSED");
        require(root != bytes32(0), "ROOT_ZERO");
        require(emissionAmount != 0, "EMISSION_ZERO");

        EpochEmission storage emission = epochs[epoch];
        require(!emission.published, "EPOCH_ALREADY_PUBLISHED");
        require(totalRevenueUsdc <= type(uint128).max, "TOTAL_REVENUE_TOO_LARGE");
        require(emissionAmount <= type(uint128).max, "EMISSION_TOO_LARGE");

        emission.root = root;
        emission.manifestHash = manifestHash;
        emission.totalRevenueUsdc = uint128(totalRevenueUsdc);
        emission.emissionAmount = uint128(emissionAmount);
        emission.published = true;

        regent.safeTransferFrom(msg.sender, address(this), emissionAmount);

        emit EpochPublished(epoch, totalRevenueUsdc, emissionAmount, root, manifestHash);
    }

    function claim(
        uint32 epoch,
        uint256 index,
        bytes32 subjectId,
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) external whenNotPaused nonReentrant returns (uint256 claimed) {
        claimed = _claim(epoch, index, subjectId, recipient, amount, proof);
    }

    function claimMany(
        uint32[] calldata epochs_,
        uint256[] calldata indexes,
        bytes32[] calldata subjectIds,
        address[] calldata recipients,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external whenNotPaused nonReentrant returns (uint256 totalClaimed) {
        uint256 length = epochs_.length;
        require(
            length == indexes.length && length == subjectIds.length && length == recipients.length
                && length == amounts.length && length == proofs.length,
            "LENGTH_MISMATCH"
        );

        for (uint256 i; i < length; ++i) {
            totalClaimed += _claim(
                epochs_[i], indexes[i], subjectIds[i], recipients[i], amounts[i], proofs[i]
            );
        }
    }

    function _claim(
        uint32 epoch,
        uint256 index,
        bytes32 subjectId,
        address recipient,
        uint256 amount,
        bytes32[] calldata proof
    ) internal returns (uint256 claimed) {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(subjectId != bytes32(0), "SUBJECT_ZERO");
        require(!_isClaimed(epoch, index), "ALREADY_CLAIMED");
        require(!subjectClaimed[epoch][subjectId], "SUBJECT_ALREADY_CLAIMED");

        EpochEmission memory emission = epochs[epoch];
        require(emission.published, "EPOCH_NOT_PUBLISHED");

        bytes32 leaf = keccak256(abi.encode(index, subjectId, recipient, amount));
        require(MerkleProofLib.verify(proof, emission.root, leaf), "INVALID_PROOF");

        _setClaimed(epoch, index);
        subjectClaimed[epoch][subjectId] = true;

        claimed = amount;
        regent.safeTransfer(recipient, claimed);

        emit Claimed(epoch, index, subjectId, recipient, claimed);
    }

    function _setRole(bytes32 role, address account, bool enabled) internal {
        require(account != address(0), "ACCOUNT_ZERO");
        roles[role][account] = enabled;
        emit RoleSet(role, account, enabled);
    }

    function _isClaimed(uint32 epoch, uint256 index) internal view returns (bool) {
        uint256 wordIndex = index >> 8;
        uint256 bitIndex = index & 255;
        uint256 word = claimedBitMap[epoch][wordIndex];
        uint256 mask = 1 << bitIndex;
        return word & mask == mask;
    }

    function _setClaimed(uint32 epoch, uint256 index) internal {
        uint256 wordIndex = index >> 8;
        uint256 bitIndex = index & 255;
        claimedBitMap[epoch][wordIndex] |= 1 << bitIndex;
    }
}
