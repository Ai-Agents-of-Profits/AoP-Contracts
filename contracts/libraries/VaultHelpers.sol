// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AoP1VaultHelpers.sol";
import "./AoP2VaultHelpers.sol";

/**
 * @title VaultHelpers
 * @dev Library containing general helper functions for vault interactions
 */
library VaultHelpers {
    /**
     * @dev Add an agent to a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to add
     * @param isAoP1Vault Boolean indicating if the vault is an AoP1Vault
     */
    function addAgentToVault(
        address vaultAddress,
        address agent,
        bool isAoP1Vault
    ) external {
        if (isAoP1Vault) {
            AoP1VaultHelpers.addAgent(vaultAddress, agent);
        } else {
            AoP2VaultHelpers.addAgent(vaultAddress, agent);
        }
    }
    
    /**
     * @dev Remove an agent from a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to remove
     * @param isAoP1Vault Boolean indicating if the vault is an AoP1Vault
     */
    function removeAgentFromVault(
        address vaultAddress,
        address agent,
        bool isAoP1Vault
    ) external {
        if (isAoP1Vault) {
            AoP1VaultHelpers.removeAgent(vaultAddress, agent);
        } else {
            AoP2VaultHelpers.removeAgent(vaultAddress, agent);
        }
    }
    
    /**
     * @dev Update the fee recipient for a vault
     * @param vaultAddress Address of the vault
     * @param newFeeRecipient New fee recipient
     * @param isAoP1Vault Boolean indicating if the vault is an AoP1Vault
     */
    function updateFeeRecipient(
        address vaultAddress,
        address newFeeRecipient,
        bool isAoP1Vault
    ) external {
        if (isAoP1Vault) {
            AoP1VaultHelpers.updateFeeRecipient(vaultAddress, newFeeRecipient);
        } else {
            AoP2VaultHelpers.updateFeeRecipient(vaultAddress, newFeeRecipient);
        }
    }
    
    /**
     * @dev Gets historical NAV data from a vault
     * @param vaultAddress Address of the vault
     * @return timestamps Array of timestamps
     * @return values Array of NAV values
     * @return totalValues Array of total vault values
     */
    function getHistoricalNAV(
        address vaultAddress,
        bool isAoP1Vault
    ) external view returns (
        uint256[] memory timestamps,
        uint256[] memory values,
        uint256[] memory totalValues
    ) {
        if (isAoP1Vault) {
            return AoP1VaultHelpers.getHistoricalNAV(vaultAddress);
        } else {
            return AoP2VaultHelpers.getHistoricalNAV(vaultAddress);
        }
    }
}
