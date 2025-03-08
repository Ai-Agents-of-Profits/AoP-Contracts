// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAgentVault
 * @dev Interface for interaction between Agent system and the vaults (AoP1Vault and AoP2Vault)
 * @notice All vaults handle decimal precision consistently:
 *         - Share tokens use 18 decimals (standard for ERC20)
 *         - USDT uses 6 decimals
 *         - Appropriate scaling factors are applied internally
 */
interface IAgentVault {
    /**
     * @dev Returns the total value of the vault
     * @return Value with 6 decimals precision (USDT)
     */
    function getTotalVaultValue() external view returns (uint256);
    
    /**
     * @dev Get the current share price (NAV per share)
     * @return Share price with 18 decimals precision
     */
    function getSharePrice() external view returns (uint256);
    
    /**
     * @dev Returns the total number of active users in the vault
     * @return Count of active users with non-zero balances
     */
    function getTotalUsers() external view returns (uint256);
}

/**
 * @title IAoP1Vault
 * @dev Interface for interaction with AoP1Vault which supports MON (native token) and USDT
 */
interface IAoP1Vault is IAgentVault {
    /**
     * @dev Allows an agent to request funds for trading
     * @param amount Amount to request (native units: wei for MON, or 6 decimals for USDT)
     * @param isMon Whether to request MON or USDT
     */
    function requestFunds(uint256 amount, bool isMon) external;
    
    /**
     * @dev Allows an agent to return funds and distribute profits
     * @param profit The profit amount in USDT or MON (native units: wei for MON, or 6 decimals for USDT)
     * @param isMon Whether the profit is in MON or USDT
     */
    function returnFundsWithProfit(uint256 profit, bool isMon, bytes[] calldata) external payable;
    
    /**
     * @dev Allows users to withdraw their shares
     * @param shareAmount Amount of shares to withdraw (18 decimals)
     * @param withdrawAsMon Whether to withdraw in MON or USDT
     */
    function withdraw(uint256 shareAmount, bool withdrawAsMon, bytes[] calldata) external payable;
}

/**
 * @title IAoP2Vault
 * @dev Interface for interaction with AoP2Vault which only supports USDT (6 decimals)
 */
interface IAoP2Vault is IAgentVault {
    /**
     * @dev Allows an agent to request funds for trading
     * @param amount Amount to request (6 decimals for USDT)
     */
    function requestFunds(uint256 amount) external;
    
    /**
     * @dev Allows an agent to return funds and distribute profits
     * @param originalAmount The original amount that was requested (6 decimals)
     * @param profit The profit amount in USDT (6 decimals)
     */
    function returnFundsWithProfit(uint256 originalAmount, uint256 profit) external;
    
    /**
     * @dev Allows users to withdraw their shares
     * @param shareAmount Amount of shares to withdraw (18 decimals)
     */
    function withdraw(uint256 shareAmount) external;
}
