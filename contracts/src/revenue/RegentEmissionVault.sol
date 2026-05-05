// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Owned} from "src/auth/Owned.sol";
import {SafeTransferLib} from "src/libraries/SafeTransferLib.sol";
import {IERC20SupplyMinimal} from "src/revenue/interfaces/IERC20SupplyMinimal.sol";
import {IRegentEmissionVault} from "src/revenue/interfaces/IRegentEmissionVault.sol";

contract RegentEmissionVault is Owned, IRegentEmissionVault {
    using SafeTransferLib for address;

    address public immutable override regent;
    address public router;

    event RouterSet(address indexed router);
    event RegentFunded(address indexed caller, uint256 amountReceived);
    event RegentEmitted(
        bytes32 indexed subjectId,
        address indexed recipient,
        uint256 amount,
        bytes32 indexed sourceRef
    );

    modifier onlyRouter() {
        require(msg.sender == router, "ONLY_ROUTER");
        _;
    }

    constructor(address regent_, address owner_) Owned(owner_) {
        require(regent_ != address(0), "REGENT_ZERO");
        regent = regent_;
    }

    function setRouter(address router_) external onlyOwner {
        require(router_ != address(0), "ROUTER_ZERO");
        router = router_;
        emit RouterSet(router_);
    }

    function fundRegent(uint256 amount) external returns (uint256 received) {
        require(amount != 0, "AMOUNT_ZERO");
        uint256 beforeBalance = IERC20SupplyMinimal(regent).balanceOf(address(this));
        regent.safeTransferFrom(msg.sender, address(this), amount);
        uint256 afterBalance = IERC20SupplyMinimal(regent).balanceOf(address(this));
        received = afterBalance - beforeBalance;
        require(received == amount, "REGENT_IN_EXACT");
        emit RegentFunded(msg.sender, received);
    }

    function availableRegent() public view override returns (uint256) {
        return IERC20SupplyMinimal(regent).balanceOf(address(this));
    }

    function emitRegent(address recipient, uint256 amount, bytes32 subjectId, bytes32 sourceRef)
        external
        override
        onlyRouter
    {
        require(recipient != address(0), "RECIPIENT_ZERO");
        require(recipient != address(this), "RECIPIENT_IS_SELF");
        require(amount != 0, "AMOUNT_ZERO");
        require(availableRegent() >= amount, "REGENT_INVENTORY_LOW");

        regent.safeTransfer(recipient, amount);
        emit RegentEmitted(subjectId, recipient, amount, sourceRef);
    }

    function _isProtectedToken(address token) internal view override returns (bool) {
        return token == regent;
    }
}
