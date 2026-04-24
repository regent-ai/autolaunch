// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library BaseFamilyUSDC {
    uint256 internal constant BASE_MAINNET_CHAIN_ID = 8453;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84_532;

    address internal constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function canonicalUsdc(uint256 chainId) internal pure returns (address) {
        if (chainId == BASE_MAINNET_CHAIN_ID) return BASE_MAINNET_USDC;
        if (chainId == BASE_SEPOLIA_CHAIN_ID) return BASE_SEPOLIA_USDC;
        revert("BASE_FAMILY_ONLY");
    }

    function requireCanonical(address usdc) internal view {
        require(usdc == canonicalUsdc(block.chainid), "USDC_NOT_CANONICAL");
    }
}
