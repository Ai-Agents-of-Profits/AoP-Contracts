// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/**
 * @title AoP1Vault
 * @dev A vault contract that accepts MON and USDT deposits, issues share tokens,
 * and allows approved agents to manage funds and distribute profits.
 */
contract AoP1Vault is ERC20, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // Constants for performance fee calculation
    uint256 public constant PERFORMANCE_FEE_PERCENTAGE = 2000; // 20% in basis points (10000 = 100%)
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_HISTORY_ITEMS = 100;
    
    // Constants for decimal handling
    uint256 public constant SHARE_DECIMALS = 18; // Share token uses 18 decimals
    uint256 public constant USDT_DECIMALS = 6;   // USDT uses 6 decimals
    uint256 public constant MON_DECIMALS = 18;   // MON uses 18 decimals
    uint256 public constant SCALING_FACTOR = 10 ** (SHARE_DECIMALS - USDT_DECIMALS); // 10^12
    
    // Roles
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // State variables
    address public usdtToken;
    uint256 public navPerShare; // Net Asset Value per share (18 decimals)
    uint256 public totalVaultValue; // Total value in the vault (USDT, which has 6 decimals)
    uint256 public lastNavUpdate; // Timestamp of the last NAV update
    uint256 public totalMonValue; // Total MON value in wei
    
    // Pyth Network integration
    IPyth public pyth;
    bytes32 public monUsdPriceId;
    
    // Fee recipient
    address public feeRecipient;
    
    // User tracking
    mapping(address => bool) public isActiveUser;
    uint256 public totalUsers;
    
    // Historical tracking
    struct NAVSnapshot {
        uint256 timestamp;
        uint256 navValue;     // Stored with 18 decimals precision
        uint256 totalValue;   // Stored with 6 decimals precision (USDT)
    }
    NAVSnapshot[] public navHistory;
    
    // User tracking
    struct UserDeposit {
        uint256 monAmount;
        uint256 usdtAmount;
        uint256 initialTimestamp;
        uint256 lastDepositTimestamp;
    }
    mapping(address => UserDeposit) public userDeposits;
    
    // Events
    event Deposit(address indexed user, uint256 amount, bool isMon, uint256 sharesIssued);
    event Withdrawal(address indexed user, uint256 amount, bool isMon, uint256 sharesBurned);
    event ProfitDistributed(uint256 profit, uint256 performanceFee);
    event NavUpdated(uint256 oldNav, uint256 newNav);
    event AgentFundRequest(address indexed agent, uint256 amount, bool isMon);
    event FundsReturned(address indexed agent, uint256 amount, bool isMon);
    event SharePriceUpdated(uint256 oldPrice, uint256 newPrice, uint256 timestamp);
    event PerformanceMetrics(
        uint256 totalValue, 
        uint256 totalShares, 
        uint256 sharePrice, 
        uint256 monBalance, 
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
    event PythContractUpdated(address newPythContract);
    event MonUsdPriceIdUpdated(bytes32 newMonUsdPriceId);
    event NavPerShareUpdated(uint256 newNavPerShare);
    
    /**
     * @dev Constructor to initialize the vault
     * @param _name Name of the share token
     * @param _symbol Symbol of the share token
     * @param _usdtToken Address of the USDT token
     * @param _feeRecipient Address to receive performance fees
     * @param _pythContract Address of the Pyth Network contract
     * @param _monUsdPriceId Price feed ID for MON/USD
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _usdtToken,
        address _feeRecipient,
        address _pythContract,
        bytes32 _monUsdPriceId
    ) ERC20(_name, _symbol) {
        require(_usdtToken != address(0), "USDT address cannot be zero");
        require(_feeRecipient != address(0), "Fee recipient cannot be zero");
        require(_pythContract != address(0), "Pyth contract cannot be zero");
        
        usdtToken = _usdtToken;
        feeRecipient = _feeRecipient;
        pyth = IPyth(_pythContract);
        monUsdPriceId = _monUsdPriceId;
        
        navPerShare = 10 ** SHARE_DECIMALS; // Initialize NAV at 1.0 (using 18 decimals)
        lastNavUpdate = block.timestamp;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Gets the MON/USD price from the Pyth Network oracle.
     * @param priceUpdateData Optional price update data from Pyth Network.
     * @return The MON/USD price with 6 decimals precision as int128.
     */
    function getMonUsdPrice(bytes[] calldata priceUpdateData) public payable returns (int128) {
        // Update price feed if update data is provided
        if (priceUpdateData.length > 0) {
            uint256 fee = pyth.getUpdateFee(priceUpdateData);
            pyth.updatePriceFeeds{value: fee}(priceUpdateData);
        }
        
        // Get price from Pyth allowing data up to 60 seconds stale
        PythStructs.Price memory priceData = pyth.getPriceNoOlderThan(monUsdPriceId, 60);
        
        // Convert from Pyth's fixed-point representation to our int128
        int128 price;
        
        if (priceData.price < 0) {
            return 0; // Safeguard for negative prices
        }
        
        // Scale price to USDT decimals (6) instead of 18 decimals
        int expoAdjustment = 6 + priceData.expo; // Adjusting to 6 decimals for USDT
        
        // Use a safer approach with int256 to avoid overflow
        int256 safePrice = int256(priceData.price);
        
        if (expoAdjustment > 0) {
            // Calculate 10^expoAdjustment first (can use a loop for simplicity)
            int256 scaleFactor = 1;
            for (int i = 0; i < expoAdjustment && i < 59; i++) { // Cap at 59 to avoid overflow
                scaleFactor *= 10;
            }
            
            // Safely multiply
            safePrice = safePrice * scaleFactor;
            
            // Check if the result is within int128 range
            if (safePrice > int256(type(int128).max)) {
                price = type(int128).max;
            } else {
                price = int128(safePrice);
            }
        } else if (expoAdjustment < 0) {
            // For negative exponents, divide by 10^(-expoAdjustment)
            int256 scaleFactor = 1;
            for (int i = 0; i > expoAdjustment && i > -59; i--) { // Cap at -59 to avoid issues
                scaleFactor *= 10;
            }
            
            // Safe division
            safePrice = safePrice / scaleFactor;
            price = int128(safePrice);
        } else {
            price = int128(safePrice);
        }
        
        return price;
    }
    
    /**
     * @dev Gets the MON/USD price without updating the price feed.
     * @return The MON/USD price with 6 decimals precision.
     */
    function getMonUsdPriceView() public view returns (int128) {
        try pyth.getPriceUnsafe(monUsdPriceId) returns (PythStructs.Price memory priceData) {
            // Convert from Pyth's fixed-point representation to our int128
            int128 price;
            
            if (priceData.price < 0) {
                return 0; // Safeguard for negative prices
            }
            
            // Scale price to USDT decimals (6) instead of 18 decimals
            int expoAdjustment = 6 + priceData.expo; // Adjusting to 6 decimals for USDT
            
            // Use a safer approach with int256 to avoid overflow
            int256 safePrice = int256(priceData.price);
            
            if (expoAdjustment > 0) {
                // Calculate 10^expoAdjustment first (can use a loop for simplicity)
                int256 scaleFactor = 1;
                for (int i = 0; i < expoAdjustment && i < 59; i++) { // Cap at 59 to avoid overflow
                    scaleFactor *= 10;
                }
                
                // Safely multiply
                safePrice = safePrice * scaleFactor;
                
                // Check if the result is within int128 range
                if (safePrice > int256(type(int128).max)) {
                    price = type(int128).max;
                } else {
                    price = int128(safePrice);
                }
            } else if (expoAdjustment < 0) {
                // For negative exponents, divide by 10^(-expoAdjustment)
                int256 scaleFactor = 1;
                for (int i = 0; i > expoAdjustment && i > -59; i--) { // Cap at -59 to avoid issues
                    scaleFactor *= 10;
                }
                
                // Safe division
                safePrice = safePrice / scaleFactor;
                price = int128(safePrice);
            } else {
                price = int128(safePrice);
            }
            
            return price;
        } catch {
            return 1e6; // Fallback to 1:1 if price fetch fails
        }
    }
    
    /**
     * @dev Converts MON amount to USDT equivalent using the current price from Pyth.
     * @param monAmount The amount of MON to convert.
     * @param priceUpdateData Optional price update data from Pyth Network.
     * @return The equivalent USDT amount.
     */
    function convertMonToUsdt(uint256 monAmount, bytes[] calldata priceUpdateData) public payable returns (uint256) {
        int128 monPrice = getMonUsdPrice(priceUpdateData);
        uint256 monPriceUint;
        if (monPrice > 0) {
            assembly {
                monPriceUint := monPrice
            }
        }
        // Convert from 18 decimals (MON) to 6 decimals (USDT) using the price with 6 decimals
        return monAmount * monPriceUint / (10 ** MON_DECIMALS);
    }
    
    /**
     * @dev Converts MON amount to USDT equivalent using the current cached price.
     * @param monAmount The amount of MON to convert.
     * @return The equivalent USDT amount.
     */
    function convertMonToUsdtView(uint256 monAmount) public view returns (uint256) {
        int128 monPrice = getMonUsdPriceView();
        uint256 monPriceUint;
        if (monPrice > 0) {
            assembly {
                monPriceUint := monPrice
            }
        }
        // Convert from 18 decimals (MON) to 6 decimals (USDT) using the price with 6 decimals
        return monAmount * monPriceUint / (10 ** MON_DECIMALS);
    }
    
    /**
     * @dev Allows users to deposit USDT into the vault.
     * Uses a continuous share formula where shares = deposit_value / current_share_price.
     * @param amount Amount of USDT to deposit.
     */
    function depositUSDT(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        // Calculate shares based on current vault value
        uint256 sharesToIssue = _calculateSharesToIssue(amount, false);
        
        IERC20(usdtToken).safeTransferFrom(msg.sender, address(this), amount);
        totalVaultValue += amount;
        _mint(msg.sender, sharesToIssue);
        
        emit Deposit(msg.sender, amount, false, sharesToIssue);
        
        // Track active users
        if (!isActiveUser[msg.sender]) {
            isActiveUser[msg.sender] = true;
            totalUsers++;
        }
        
        UserDeposit storage userDeposit = userDeposits[msg.sender];
        if (userDeposit.initialTimestamp == 0) {
            userDeposit.initialTimestamp = block.timestamp;
        }
        userDeposit.usdtAmount += amount;
        userDeposit.lastDepositTimestamp = block.timestamp;
        
        _updateUserMetrics(msg.sender);
    }
    
    /**
     * @dev Convenience function for depositing MON without providing price update data.
     * @notice This will use the latest available price from the oracle.
     */
    function depositMON() external payable {
        bytes[] memory emptyPriceData = new bytes[](0);
        this.depositMON(emptyPriceData);
    }
    
    /**
     * @dev Allows users to deposit MON into the vault.
     * MON is valued at its current USDT price via Pyth oracle.
     * @param priceUpdateData Optional price update data from Pyth Network.
     */
    function depositMON(bytes[] calldata priceUpdateData) external payable nonReentrant {
        require(msg.value > 0, "MON amount must be greater than 0");
        
        // Calculate USDT-equivalent value of the MON deposit
        uint256 usdtEquivalentValue = convertMonToUsdt(msg.value, priceUpdateData);
        require(usdtEquivalentValue > 0, "MON USDT equivalent value must be greater than 0");
        
        // Calculate shares based on current vault value
        uint256 sharesToIssue = _calculateSharesToIssue(usdtEquivalentValue, true);
        
        totalMonValue += msg.value;
        _mint(msg.sender, sharesToIssue);
        
        emit Deposit(msg.sender, msg.value, true, sharesToIssue);
        
        // Track active users
        if (!isActiveUser[msg.sender]) {
            isActiveUser[msg.sender] = true;
            totalUsers++;
        }
        
        UserDeposit storage userDeposit = userDeposits[msg.sender];
        if (userDeposit.initialTimestamp == 0) {
            userDeposit.initialTimestamp = block.timestamp;
        }
        userDeposit.monAmount += msg.value;
        userDeposit.lastDepositTimestamp = block.timestamp;
        
        _updateUserMetrics(msg.sender);
    }
    
    /**
     * @dev Internal function to calculate shares to issue for a deposit.
     * @param depositValue Value of the deposit in USDT terms (may need to be pre-converted for MON).
     * @param isMon Whether this calculation is for a MON deposit.
     * @return Number of shares to issue.
     */
    function _calculateSharesToIssue(uint256 depositValue, bool isMon) internal view returns (uint256) {
        uint256 totalSupplyAmount = totalSupply();
        
        // If this is the first deposit, initialize share price to 1 USDT = 1 share
        if (totalSupplyAmount == 0) {
            // Scale to 18 decimals from USDT's 6 decimals
            return depositValue * SCALING_FACTOR;
        }
        
        // Calculate total vault value in USDT terms before this deposit
        uint256 vaultValueInUsdt = getTotalValueInUsdt();
        
        // If vault has MON but no current price, or if vault is empty, default to 1:1
        if (vaultValueInUsdt == 0) {
            return depositValue * SCALING_FACTOR;
        }
        
        // Calculate: shares = (deposit / total_vault_value) * total_supply
        // This ensures proportional ownership of the vault
        return (depositValue * totalSupplyAmount) / vaultValueInUsdt;
    }
    
    /**
     * @dev Calculates the total vault value in USDT, including both USDT and MON holdings.
     * @return Total vault value in USDT terms (with 6 decimals).
     */
    function getTotalValueInUsdt() public view returns (uint256) {
        // Value of USDT holdings (already in USDT terms)
        uint256 usdtValue = totalVaultValue;
        
        // Value of MON holdings converted to USDT
        uint256 monUsdtValue = 0;
        if (totalMonValue > 0) {
            int128 monPrice = getMonUsdPriceView();
            if (monPrice > 0) {
                uint256 monPriceUint;
                assembly {
                    monPriceUint := monPrice
                }
                // Convert MON value to USDT value (with 6 decimals)
                monUsdtValue = (totalMonValue * monPriceUint) / (10 ** MON_DECIMALS);
            }
        }
        
        return usdtValue + monUsdtValue;
    }
    
    /**
     * @dev Calculate the current price per share in USDT terms.
     * @return Current price per share with 18 decimals.
     */
    function getPricePerShare() public view returns (uint256) {
        uint256 totalSupplyAmount = totalSupply();
        if (totalSupplyAmount == 0) {
            return 10 ** SHARE_DECIMALS; // Default to 1.0 if no shares exist
        }
        
        uint256 totalValueUsdt = getTotalValueInUsdt();
        
        // Convert total value from USDT (6 decimals) to the standard share decimal precision (18)
        uint256 totalValueScaled = totalValueUsdt * SCALING_FACTOR;
        
        // Calculate price per share with proper precision
        return (totalValueScaled * (10 ** SHARE_DECIMALS)) / totalSupplyAmount;
    }
    
    /**
     * @dev Updates the internal navPerShare value based on current vault assets.
     * This should be called after significant value changes, such as profits from trading.
     */
    function updateNavPerShare() public {
        navPerShare = getPricePerShare();
        emit NavPerShareUpdated(navPerShare);
    }
    
    /**
     * @dev Allows users to withdraw their shares.
     * @param shareAmount Amount of shares to withdraw.
     * @param withdrawAsMon Whether to withdraw in MON or USDT.
     * @param priceUpdateData Optional price update data from Pyth Network.
     */
    function withdraw(uint256 shareAmount, bool withdrawAsMon, bytes[] calldata priceUpdateData) external payable nonReentrant {
        require(shareAmount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= shareAmount, "Insufficient shares");
        
        // Update NAV per share before withdrawal
        updateNavPerShare();
        
        // Calculate the value of shares in USDT terms (with 6 decimals)
        uint256 totalSupplyAmount = totalSupply();
        uint256 totalVaultUsdtValue = getTotalValueInUsdt();
        
        // Calculate proportional value: value = (shares / total_supply) * total_vault_value
        uint256 withdrawalValueUsdt = (shareAmount * totalVaultUsdtValue) / totalSupplyAmount;
        
        if (withdrawAsMon) {
            // Convert USDT value to MON based on current price
            int128 monPrice = getMonUsdPrice(priceUpdateData);
            uint256 monPriceUint;
            if (monPrice > 0) {
                assembly {
                    monPriceUint := monPrice
                }
            }
            require(monPriceUint > 0, "Invalid MON price");
            
            // Convert USDT value to MON value
            uint256 withdrawalValueMon = (withdrawalValueUsdt * (10 ** MON_DECIMALS)) / monPriceUint;
            
            require(withdrawalValueMon <= totalMonValue, "Insufficient MON liquidity");
            totalMonValue -= withdrawalValueMon;
            _burn(msg.sender, shareAmount);
            
            (bool success, ) = msg.sender.call{value: withdrawalValueMon}("");
            require(success, "MON transfer failed");
            
            emit Withdrawal(msg.sender, withdrawalValueMon, true, shareAmount);
        } else {
            require(withdrawalValueUsdt <= IERC20(usdtToken).balanceOf(address(this)), "Insufficient USDT liquidity");
            
            _burn(msg.sender, shareAmount);
            IERC20(usdtToken).safeTransfer(msg.sender, withdrawalValueUsdt);
            totalVaultValue -= withdrawalValueUsdt;
            
            emit Withdrawal(msg.sender, withdrawalValueUsdt, false, shareAmount);
        }
        
        // If user has no more shares, they're no longer an active user
        if (balanceOf(msg.sender) == 0) {
            isActiveUser[msg.sender] = false;
            totalUsers--;
        }
        
        _updateUserMetrics(msg.sender);
    }
    
    /**
     * @dev Updates user metrics after a deposit or withdrawal.
     */
    function _updateUserMetrics(address user) internal {
        uint256 shares = balanceOf(user);
        uint256 currentValue = (shares * navPerShare) / (10 ** SHARE_DECIMALS);
        
        UserDeposit memory userDeposit = userDeposits[user];
        // Scale USDT deposits from 6 decimals to 18 for accurate comparison
        uint256 scaledUsdtDeposits = userDeposit.usdtAmount * SCALING_FACTOR;
        uint256 totalDeposits = scaledUsdtDeposits;
        
        // Add MON deposits converted to USDT equivalent
        if (userDeposit.monAmount > 0) {
            int128 monPrice = getMonUsdPriceView();
            uint256 monPriceUint;
            if (monPrice > 0) {
                assembly {
                    monPriceUint := monPrice
                }
            }
            totalDeposits += userDeposit.monAmount * monPriceUint / (10 ** MON_DECIMALS);
        }
        
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
     * @dev Get detailed information about a user's position.
     */
    function getUserDetails(address user) external view returns (
        uint256 shares,
        uint256 valueInUSDT,
        uint256 percentageOfVault,
        uint256 profitSinceDeposit,
        uint256 initialDepositDate,
        uint256 monDeposited,
        uint256 usdtDeposited
    ) {
        shares = balanceOf(user);
        valueInUSDT = (shares * navPerShare) / (10 ** SHARE_DECIMALS);
        percentageOfVault = totalSupply() > 0 ? (shares * BASIS_POINTS) / totalSupply() : 0;
        
        UserDeposit memory userDeposit = userDeposits[user];
        
        // Scale USDT deposits from 6 decimals to 18 for accurate comparison
        uint256 scaledUsdtDeposits = userDeposit.usdtAmount * SCALING_FACTOR;
        uint256 totalDeposits = scaledUsdtDeposits;
        
        if (userDeposit.monAmount > 0) {
            int128 monPrice = getMonUsdPriceView();
            uint256 monPriceUint;
            if (monPrice > 0) {
                assembly {
                    monPriceUint := monPrice
                }
            }
            totalDeposits += userDeposit.monAmount * monPriceUint / (10 ** MON_DECIMALS);
        }
        
        profitSinceDeposit = valueInUSDT > totalDeposits ? valueInUSDT - totalDeposits : 0;
        initialDepositDate = userDeposit.initialTimestamp;
        monDeposited = userDeposit.monAmount;
        usdtDeposited = userDeposit.usdtAmount;
    }
    
    /**
     * @dev Returns the total number of users with non-zero balances.
     */
    function getTotalUsers() external view returns (uint256) {
        return totalUsers;
    }
    
    /**
     * @dev Returns the total value of the vault in USDT.
     */
    function getTotalVaultValue() external view returns (uint256) {
        return totalVaultValue;
    }
    
    /**
     * @dev Get the user's share value in USDT.
     * @param user Address of the user.
     */
    function getUserShareValue(address user) external view returns (uint256) {
        uint256 userShares = balanceOf(user);
        return (userShares * navPerShare) / (10 ** SHARE_DECIMALS);
    }
    
    /**
     * @dev Get the current share price (NAV per share).
     */
    function getSharePrice() external view returns (uint256) {
        return navPerShare;
    }
    
    /**
     * @dev Get the current MON/USDT price.
     */
    function getCurrentMonPrice() external view returns (int128) {
        return getMonUsdPriceView();
    }
    
    /**
     * @dev Records a NAV snapshot for historical tracking.
     */
    function _recordNAVSnapshot() internal {
        if (navHistory.length >= MAX_HISTORY_ITEMS) {
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
     * @dev Get statistics about the vault's performance.
     */
    function getVaultStatistics() external view returns (
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 totalShares,
        uint256 monBalance,
        uint256 usdtBalance,
        uint256 lastUpdateTime,
        uint256 userCount
    ) {
        return (
            totalVaultValue,
            navPerShare,
            totalSupply(),
            totalMonValue,
            IERC20(usdtToken).balanceOf(address(this)),
            lastNavUpdate,
            totalUsers
        );
    }
    
    /**
     * @dev Get historical NAV data for charting.
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
     * @dev Allows the contract to receive MON.
     */
    receive() external payable {}
    
    /**
     * @dev Updates the fee recipient address.
     * @param newFeeRecipient New fee recipient address.
     */
    function setFeeRecipient(address newFeeRecipient) external onlyRole(ADMIN_ROLE) {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }
    
    /**
     * @dev Adds an agent address.
     * @param agent Address to add as agent.
     */
    function addAgent(address agent) external onlyRole(ADMIN_ROLE) {
        require(agent != address(0), "Invalid agent address");
        _grantRole(AGENT_ROLE, agent);
    }
    
    /**
     * @dev Removes an agent address.
     * @param agent Address to remove as agent.
     */
    function removeAgent(address agent) external onlyRole(ADMIN_ROLE) {
        _revokeRole(AGENT_ROLE, agent);
    }
    
    /**
     * @dev Updates the Pyth Network contract address.
     * @param _pythContract New Pyth Network contract address.
     */
    function setPythContract(address _pythContract) external onlyRole(ADMIN_ROLE) {
        require(_pythContract != address(0), "Pyth contract cannot be zero");
        pyth = IPyth(_pythContract);
        emit PythContractUpdated(_pythContract);
    }
    
    /**
     * @dev Updates the MON/USD price feed ID.
     * @param _monUsdPriceId New price feed ID.
     */
    function setMonUsdPriceId(bytes32 _monUsdPriceId) external onlyRole(ADMIN_ROLE) {
        monUsdPriceId = _monUsdPriceId;
        emit MonUsdPriceIdUpdated(_monUsdPriceId);
    }
    
    /**
     * @dev Estimates the number of shares that would be issued for a given USDT deposit.
     * @param usdtAmount Amount of USDT to deposit.
     * @return The estimated number of shares.
     */
    function estimateSharesForUsdtDeposit(uint256 usdtAmount) external view returns (uint256) {
        if (usdtAmount == 0) return 0;
        
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply == 0) {
            // For first deposit
            return usdtAmount * SCALING_FACTOR;
        } else {
            // For subsequent deposits
            return (usdtAmount * SCALING_FACTOR * (10 ** SHARE_DECIMALS)) / navPerShare;
        }
    }
    
    /**
     * @dev Estimates the number of shares that would be issued for a given MON deposit.
     * @param monAmount Amount of MON to deposit.
     * @return The estimated number of shares.
     */
    function estimateSharesForMonDeposit(uint256 monAmount) external view returns (uint256) {
        if (monAmount == 0) return 0;
        
        // Get current MON price
        int128 monPrice = getMonUsdPriceView();
        uint256 monPriceUint;
        if (monPrice > 0) {
            assembly {
                monPriceUint := monPrice
            }
        }
        if (monPriceUint == 0) return 0;
        
        // Convert MON to equivalent USDT value
        uint256 usdtEquivalentValue = monAmount * monPriceUint / (10 ** MON_DECIMALS);
        
        uint256 currentTotalSupply = totalSupply();
        if (currentTotalSupply == 0) {
            // For first deposit
            return usdtEquivalentValue * SCALING_FACTOR;
        } else {
            // For subsequent deposits
            return (usdtEquivalentValue * SCALING_FACTOR * (10 ** SHARE_DECIMALS)) / navPerShare;
        }
    }
    
    /**
     * @dev Allows an agent to request funds for trading.
     * @param amount Amount to request.
     * @param isMon Whether to request MON or USDT.
     */
    function requestFunds(uint256 amount, bool isMon) external nonReentrant onlyRole(AGENT_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        
        if (isMon) {
            require(amount <= totalMonValue, "Insufficient MON in vault");
            totalMonValue -= amount;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "MON transfer failed");
        } else {
            require(amount <= IERC20(usdtToken).balanceOf(address(this)), "Insufficient USDT in vault");
            IERC20(usdtToken).safeTransfer(msg.sender, amount);
        }
        
        emit AgentFundRequest(msg.sender, amount, isMon);
    }
    
    /**
     * @dev Allows an agent to return funds and distribute profits.
     * @param profit The profit amount in USDT or MON.
     * @param isMon Whether the profit is in MON or USDT.
     * @param priceUpdateData Optional price update data from Pyth Network.
     */
    function returnFundsWithProfit(uint256 profit, bool isMon, bytes[] calldata priceUpdateData) external payable nonReentrant onlyRole(AGENT_ROLE) {
        require(profit > 0, "Profit must be greater than 0");
        
        uint256 returnedAmount;
        uint256 usdtEquivalentProfit;
        
        if (isMon) {
            require(msg.value > 0, "MON must be sent");
            returnedAmount = msg.value;
            // First convert MON profit to USDT equivalent using Pyth price feed
            usdtEquivalentProfit = convertMonToUsdt(profit, priceUpdateData);
            
            // Calculate performance fee in MON
            uint256 monPerformanceFee = (profit * PERFORMANCE_FEE_PERCENTAGE) / BASIS_POINTS;
            if (monPerformanceFee > 0) {
                (bool success, ) = feeRecipient.call{value: monPerformanceFee}("");
                require(success, "MON fee transfer failed");
            }
            totalMonValue += (returnedAmount - monPerformanceFee);
        } else {
            usdtEquivalentProfit = profit; // Already in USDT
            uint256 performanceFee = (usdtEquivalentProfit * PERFORMANCE_FEE_PERCENTAGE) / BASIS_POINTS;
            returnedAmount = profit;
            IERC20(usdtToken).safeTransferFrom(msg.sender, address(this), returnedAmount);
            if (performanceFee > 0) {
                IERC20(usdtToken).safeTransfer(feeRecipient, performanceFee);
            }
            totalVaultValue += (returnedAmount - performanceFee);
        }
        
        // Calculate and update NAV with new profits
        uint256 oldNav = navPerShare;
        updateNavPerShare();
        
        lastNavUpdate = block.timestamp;
        
        emit FundsReturned(msg.sender, returnedAmount, isMon);
        emit ProfitDistributed(profit, (profit * PERFORMANCE_FEE_PERCENTAGE) / BASIS_POINTS);
        emit NavUpdated(oldNav, navPerShare);
        
        _recordNAVSnapshot();
        emit SharePriceUpdated(oldNav, navPerShare, block.timestamp);
        emit PerformanceMetrics(
            totalVaultValue,
            totalSupply(),
            navPerShare,
            totalMonValue,
            IERC20(usdtToken).balanceOf(address(this)),
            block.timestamp
        );
    }
}
