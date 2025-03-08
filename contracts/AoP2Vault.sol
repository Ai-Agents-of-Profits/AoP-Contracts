// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title AoP2Vault
 * @dev A simplified vault contract that accepts only USDT deposits
 */
contract AoP2Vault is ERC20, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant PERFORMANCE_FEE_PERCENTAGE = 2000; // 20% in basis points
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_HISTORY_ITEMS = 100;
    
    // Constants for decimal handling
    uint256 public constant SHARE_DECIMALS = 18; // Share token uses 18 decimals
    uint256 public constant USDT_DECIMALS = 6;   // USDT uses 6 decimals
    uint256 public constant SCALING_FACTOR = 10 ** (SHARE_DECIMALS - USDT_DECIMALS); // 10^12

    // State variables
    address public usdtToken;
    uint256 public navPerShare;
    uint256 public totalVaultValue;
    uint256 public lastNavUpdate;
    address public feeRecipient;

    // Roles
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Historical tracking
    struct NAVSnapshot {
        uint256 timestamp;
        uint256 navValue;     // Stored with 18 decimals precision
        uint256 totalValue;   // Stored with 6 decimals precision (USDT)
    }
    NAVSnapshot[] public navHistory;

    // User tracking
    struct UserDeposit {
        uint256 amount;
        uint256 initialTimestamp;
        uint256 lastDepositTimestamp;
    }
    mapping(address => UserDeposit) public userDeposits;
    mapping(address => bool) public isActiveUser;
    uint256 public totalUsers;

    // Events
    event Deposit(address indexed user, uint256 amount, uint256 sharesIssued);
    event Withdrawal(address indexed user, uint256 amount, uint256 sharesBurned);
    event ProfitDistributed(uint256 profit, uint256 performanceFee);
    event NavUpdated(uint256 oldNav, uint256 newNav);
    event AgentFundRequest(address indexed agent, uint256 amount);
    event FundsReturned(address indexed agent, uint256 amount, uint256 profit);
    event SharePriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    event PerformanceMetrics(
        uint256 totalValue,
        uint256 totalShares,
        uint256 sharePrice,
        uint256 usdtBalance,
        uint256 timestamp
    );
    event UserMetricsUpdated(
        address indexed user,
        uint256 totalShares,
        uint256 currentValue,
        uint256 profitAmount,
        uint256 timestamp
    );

    /**
     * @dev Constructor to initialize the vault
     * @param _name Name of the share token
     * @param _symbol Symbol of the share token
     * @param _usdtToken Address of the USDT token
     * @param _feeRecipient Address to receive performance fees
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdtToken,
        address _feeRecipient
    ) ERC20(_name, _symbol) {
        require(_usdtToken != address(0), "Invalid USDT address");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        
        usdtToken = _usdtToken;
        feeRecipient = _feeRecipient;
        navPerShare = 10 ** SHARE_DECIMALS; // Initialize NAV at 1.0
        lastNavUpdate = block.timestamp;
        
        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Records a NAV snapshot for historical tracking
     */
    function _recordNAVSnapshot() internal {
        if (navHistory.length >= MAX_HISTORY_ITEMS) {
            // Remove oldest entry
            for (uint i = 0; i < navHistory.length - 1; i++) {
                navHistory[i] = navHistory[i + 1];
            }
            navHistory.pop();
        }
        
        navHistory.push(NAVSnapshot({
            timestamp: block.timestamp,
            navValue: navPerShare,
            totalValue: totalVaultValue
        }));
    }

    /**
     * @dev Updates user metrics after a deposit or withdrawal
     */
    function _updateUserMetrics(address user) internal {
        uint256 shares = balanceOf(user);
        uint256 currentValue = (shares * navPerShare) / (10 ** SHARE_DECIMALS);
        
        // Scale USDT deposits from 6 decimals to 18 for accurate comparison
        uint256 totalDeposits = userDeposits[user].amount * SCALING_FACTOR;
        
        uint256 profitAmount = currentValue > totalDeposits ? currentValue - totalDeposits : 0;
        
        emit UserMetricsUpdated(
            user,
            shares,
            currentValue,
            profitAmount,
            block.timestamp
        );
    }

    /**
     * @dev Get detailed information about a user's position
     */
    function getUserDetails(address user) external view returns (
        uint256 shares,
        uint256 valueInUSDT,
        uint256 percentageOfVault,
        uint256 profitSinceDeposit,
        uint256 initialDepositDate,
        uint256 totalDeposited
    ) {
        shares = balanceOf(user);
        valueInUSDT = (shares * navPerShare) / (10 ** SHARE_DECIMALS);
        
        percentageOfVault = totalSupply() > 0 
            ? (shares * BASIS_POINTS) / totalSupply() 
            : 0;
        
        UserDeposit memory userDeposit = userDeposits[user];
        
        // Scale USDT deposits from 6 decimals to 18 for accurate comparison
        uint256 scaledDeposits = userDeposit.amount * SCALING_FACTOR;
        
        profitSinceDeposit = valueInUSDT > scaledDeposits ? valueInUSDT - scaledDeposits : 0;
        initialDepositDate = userDeposit.initialTimestamp;
        totalDeposited = userDeposit.amount;
    }

    /**
     * @dev Get statistics about the vault's performance
     */
    function getVaultStatistics() external view returns (
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 totalShares,
        uint256 usdtBalance,
        uint256 lastUpdateTime,
        uint256 activeUsers
    ) {
        return (
            totalVaultValue,
            navPerShare,
            totalSupply(),
            IERC20(usdtToken).balanceOf(address(this)),
            lastNavUpdate,
            totalUsers
        );
    }

    /**
     * @dev Get historical NAV data for charting
     */
    function getHistoricalNAV() external view returns (
        uint256[] memory timestamps,
        uint256[] memory values,
        uint256[] memory totalValues
    ) {
        uint256 length = navHistory.length;
        timestamps = new uint256[](length);
        values = new uint256[](length);
        totalValues = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            timestamps[i] = navHistory[i].timestamp;
            values[i] = navHistory[i].navValue;
            totalValues[i] = navHistory[i].totalValue;
        }
    }

    /**
     * @dev Allows users to deposit USDT into the vault
     * @param amount Amount of USDT to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
    require(amount > 0, "Amount must be greater than 0");
    
    // Get current vault stats before this new deposit
    uint256 currentTotalSupply = totalSupply();
    
    uint256 sharesToIssue;
    if (currentTotalSupply == 0) {
        // Scale the raw deposit amount to 18 decimals
        sharesToIssue = amount * SCALING_FACTOR;
        navPerShare = 10 ** SHARE_DECIMALS; // 1.0 with 18 decimals
    } else {
        // For subsequent deposits, properly scale USDT amount to match navPerShare decimals
        sharesToIssue = (amount * SCALING_FACTOR * (10 ** SHARE_DECIMALS)) / navPerShare;
    }
    
    IERC20(usdtToken).safeTransferFrom(msg.sender, address(this), amount);
    totalVaultValue += amount;
    _mint(msg.sender, sharesToIssue);
    
    // Update user deposit tracking
    if (!isActiveUser[msg.sender]) {
        isActiveUser[msg.sender] = true;
        totalUsers++;
    }
    
    UserDeposit storage userDeposit = userDeposits[msg.sender];
    if (userDeposit.initialTimestamp == 0) {
        userDeposit.initialTimestamp = block.timestamp;
    }
    userDeposit.amount += amount;
    userDeposit.lastDepositTimestamp = block.timestamp;
    
    _updateUserMetrics(msg.sender);
    emit Deposit(msg.sender, amount, sharesToIssue);
}


    /**
     * @dev Allows users to withdraw their shares directly
     * @param shares Amount of shares to withdraw
     */
    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= shares, "Insufficient shares");
        
        // Calculate the value of shares based on current NAV
        // NAV per share is in 18 decimals, need to convert to USDT's 6 decimals
        uint256 withdrawalValue = (shares * navPerShare) / (10 ** SHARE_DECIMALS);
        
        // Convert withdrawal value from 18 decimals to USDT's 6 decimals
        withdrawalValue = withdrawalValue / SCALING_FACTOR;
        
        require(withdrawalValue <= IERC20(usdtToken).balanceOf(address(this)), "Insufficient USDT liquidity");
        
        // Update total vault value
        totalVaultValue -= withdrawalValue;
        
        // Burn the shares
        _burn(msg.sender, shares);
        
        // Transfer USDT to user
        IERC20(usdtToken).safeTransfer(msg.sender, withdrawalValue);
        
        // Update user tracking only if they have no more shares
        if (balanceOf(msg.sender) == 0 && isActiveUser[msg.sender]) {
            isActiveUser[msg.sender] = false;
            totalUsers--;
        }
        
        _updateUserMetrics(msg.sender);
        emit Withdrawal(msg.sender, withdrawalValue, shares);
    }

    /**
     * @dev Allows an agent to request funds for trading
     * @param amount Amount to request
     */
    function requestFunds(uint256 amount) external nonReentrant onlyRole(AGENT_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= IERC20(usdtToken).balanceOf(address(this)), "Insufficient USDT in vault");
        
        // Transfer USDT to agent
        IERC20(usdtToken).safeTransfer(msg.sender, amount);
        
        emit AgentFundRequest(msg.sender, amount);
    }

    /**
     * @dev Allows an agent to return funds and distribute profits
     * @param originalAmount The original amount that was requested
     * @param profit The profit amount in USDT
     */
    function returnFundsWithProfit(uint256 originalAmount, uint256 profit) external nonReentrant onlyRole(AGENT_ROLE) {
        require(originalAmount > 0, "Original amount must be greater than 0");
        
        uint256 totalReturnAmount = originalAmount + profit;
        
        // Transfer returned amount plus profit from agent to vault
        IERC20(usdtToken).safeTransferFrom(msg.sender, address(this), totalReturnAmount);
        
        // Calculate performance fee
        uint256 performanceFee = (profit * PERFORMANCE_FEE_PERCENTAGE) / BASIS_POINTS;
        
        // Transfer fee to recipient
        if (performanceFee > 0) {
            IERC20(usdtToken).safeTransfer(feeRecipient, performanceFee);
        }
        
        // Update total vault value (adding profit minus the fee)
        totalVaultValue += (profit - performanceFee);
        
        // Update NAV based on new vault value
        uint256 oldNav = navPerShare;
        
        if (totalSupply() > 0) {
            // Scale totalVaultValue from 6 decimals to 18 before calculating navPerShare
            uint256 scaledTotalValue = totalVaultValue * SCALING_FACTOR;
            // Calculate new NAV per share
            navPerShare = (scaledTotalValue * (10 ** SHARE_DECIMALS)) / totalSupply();
        }
        
        // Update the last NAV update timestamp
        lastNavUpdate = block.timestamp;
        
        // Record NAV history and emit performance metrics
        _recordNAVSnapshot();
        emit SharePriceUpdated(oldNav, navPerShare, block.timestamp);
        emit PerformanceMetrics(
            totalVaultValue,
            totalSupply(),
            navPerShare,
            IERC20(usdtToken).balanceOf(address(this)),
            block.timestamp
        );
        
        emit FundsReturned(msg.sender, totalReturnAmount, profit);
        emit ProfitDistributed(profit, performanceFee);
        emit NavUpdated(oldNav, navPerShare);
    }

    /**
     * @dev Updates the fee recipient address
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyRole(ADMIN_ROLE) {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    /**
     * @dev Adds an agent address
     * @param agent Address to add as agent
     */
    function addAgent(address agent) external onlyRole(ADMIN_ROLE) {
        require(agent != address(0), "Invalid agent address");
        _grantRole(AGENT_ROLE, agent);
    }

    /**
     * @dev Removes an agent address
     * @param agent Address to remove as agent
     */
    function removeAgent(address agent) external onlyRole(ADMIN_ROLE) {
        _revokeRole(AGENT_ROLE, agent);
    }

    /**
     * @dev Returns the total value of the vault in USDT
     */
    function getTotalVaultValue() external view returns (uint256) {
        return totalVaultValue;
    }

    /**
     * @dev Returns the total number of users in the vault
     */
    function getTotalUsers() external view returns (uint256) {
        return totalUsers;
    }

    /**
     * @dev Get the current share price (NAV per share)
     */
    function getSharePrice() external view returns (uint256) {
        return navPerShare; // Returns with 18 decimals precision
    }

    /**
     * @dev Get the user's share value in USDT
     * @param user Address of the user
     */
    function getUserShareValue(address user) external view returns (uint256) {
        uint256 userShares = balanceOf(user);
        return (userShares * navPerShare) / (10 ** SHARE_DECIMALS); // Returns with 18 decimals precision
    }
}
