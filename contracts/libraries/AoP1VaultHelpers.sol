// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../AoP1Vault.sol";

/**
 * @title AoP1VaultHelpers
 * @dev Library containing helper functions for AoP1Vault interactions
 */
library AoP1VaultHelpers {
    /**
     * @dev Deploy a new AoP1Vault
     * @param name Name for the vault
     * @param symbol Token symbol for the vault
     * @param usdtToken Address of the USDT token
     * @param feeRecipient Address of the fee recipient
     * @param pythContract Address of the Pyth Network contract
     * @param monUsdPriceId Price feed ID for MON/USD
     * @return vaultAddress Address of the deployed vault
     */
    function deployVault(
        string memory name,
        string memory symbol,
        address usdtToken,
        address feeRecipient,
        address pythContract,
        bytes32 monUsdPriceId
    ) external returns (address vaultAddress) {
        AoP1Vault vault = new AoP1Vault(
            name,
            symbol,
            usdtToken,
            feeRecipient,
            pythContract,
            monUsdPriceId
        );
        return address(vault);
    }
    
    /**
     * @dev Add an agent to a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to add
     */
    function addAgent(
        address vaultAddress,
        address agent
    ) external {
        AoP1Vault(payable(vaultAddress)).addAgent(agent);
    }
    
    /**
     * @dev Remove an agent from a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to remove
     */
    function removeAgent(
        address vaultAddress,
        address agent
    ) external {
        AoP1Vault(payable(vaultAddress)).removeAgent(agent);
    }
    
    /**
     * @dev Update the fee recipient for a vault
     * @param vaultAddress Address of the vault
     * @param newFeeRecipient New fee recipient
     */
    function updateFeeRecipient(
        address vaultAddress,
        address newFeeRecipient
    ) external {
        AoP1Vault(payable(vaultAddress)).setFeeRecipient(newFeeRecipient);
    }
    
    /**
     * @dev Gets user details from AoP1Vault
     * @param vaultAddress Address of the AoP1Vault
     * @param user Address of the user
     * @return shares User's share balance
     * @return valueInUSDT Value of user's shares in USDT
     * @return percentageOfVault User's percentage of the vault
     * @return profitSinceDeposit User's profit since deposit
     * @return initialDepositDate User's initial deposit date
     * @return monDeposited Amount of MON deposited
     * @return usdtDeposited Amount of USDT deposited
     */
    function getUserDetails(
        address vaultAddress, 
        address user
    ) external view returns (
        uint256 shares,
        uint256 valueInUSDT,
        uint256 percentageOfVault,
        uint256 profitSinceDeposit,
        uint256 initialDepositDate,
        uint256 monDeposited,
        uint256 usdtDeposited
    ) {
        return AoP1Vault(payable(vaultAddress)).getUserDetails(user);
    }
    
    /**
     * @dev Gets statistics from AoP1Vault
     * @param vaultAddress Address of the AoP1Vault
     * @return totalAssets Total assets in the vault
     * @return sharePrice Current share price
     * @return totalShares Total shares issued
     * @return monBalance MON balance in the vault
     * @return usdtBalance USDT balance in the vault
     * @return lastUpdateTime Last update time of the vault
     * @return userCount Number of users in the vault
     */
    function getVaultStatistics(
        address vaultAddress
    ) external view returns (
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 totalShares,
        uint256 monBalance,
        uint256 usdtBalance,
        uint256 lastUpdateTime,
        uint256 userCount
    ) {
        return AoP1Vault(payable(vaultAddress)).getVaultStatistics();
    }
    
    /**
     * @dev Gets historical NAV data
     * @param vaultAddress Address of the vault
     * @return timestamps Array of timestamps
     * @return values Array of NAV values
     * @return totalValues Array of total vault values
     */
    function getHistoricalNAV(
        address vaultAddress
    ) external view returns (
        uint256[] memory timestamps,
        uint256[] memory values,
        uint256[] memory totalValues
    ) {
        return AoP1Vault(payable(vaultAddress)).getHistoricalNAV();
    }
}
