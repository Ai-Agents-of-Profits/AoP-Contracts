// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./libraries/AoP1VaultHelpers.sol";
import "./libraries/AoP2VaultHelpers.sol";
import "./libraries/VaultHelpers.sol"; // Import VaultHelpers after the specialized helpers
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VaultFactory
 * @dev Factory contract to deploy and manage AoP1Vault and AoP2Vault instances
 * @notice This factory handles the deployment and management of vaults with proper decimal handling:
 *         - Share tokens use 18 decimals (standard for ERC20)
 *         - USDT uses 6 decimals
 *         - Appropriate scaling factors are applied in the vault contracts
 */
contract VaultFactory is Ownable {
    // State variables
    address public usdtToken;
    address public defaultFeeRecipient;
    
    // Pyth Network parameters
    address public pythContract;
    bytes32 public monUsdPriceId;
    
    // Mapping of deployed vaults
    mapping(string => address) public vaults;
    mapping(address => bool) public isAoP1Vault;
    
    // Events
    event VaultDeployed(string name, address vaultAddress, string vaultType);
    event AgentAdded(address vault, address agent);
    event AgentRemoved(address vault, address agent);
    event FeeRecipientUpdated(address newFeeRecipient);
    event PythContractUpdated(address newPythContract);
    event MonUsdPriceIdUpdated(bytes32 newMonUsdPriceId);
    
    /**
     * @dev Constructor to initialize the factory
     * @param _usdtToken Address of the USDT token (6 decimals)
     * @param _defaultFeeRecipient Default address to receive performance fees
     * @param _pythContract Address of the Pyth Network contract
     * @param _monUsdPriceId Price feed ID for MON/USD
     */
   constructor(
    address _usdtToken, 
    address _defaultFeeRecipient,
    address _pythContract,
    bytes32 _monUsdPriceId
   ) {
        require(_usdtToken != address(0), "USDT address cannot be zero");
        require(_defaultFeeRecipient != address(0), "Fee recipient cannot be zero");
        require(_pythContract != address(0), "Pyth contract cannot be zero");
        
        usdtToken = _usdtToken;
        defaultFeeRecipient = _defaultFeeRecipient;
        pythContract = _pythContract;
        monUsdPriceId = _monUsdPriceId;
        
        // Set ownership to the message sender
        _transferOwnership(msg.sender);
   }
    
    /**
     * @dev Deploy a new AoP1Vault
     * @param _name Name of the vault
     * @param _symbol Symbol of the vault
     * @return Address of the deployed vault
     */
    function deployAoP1Vault(string memory _name, string memory _symbol) external onlyOwner returns (address) {
        require(vaults[_name] == address(0), "Vault with this name already exists");
        
        address vault = AoP1VaultHelpers.deployVault(
            _name,
            _symbol,
            usdtToken,
            defaultFeeRecipient,
            pythContract,
            monUsdPriceId
        );
        
        vaults[_name] = vault;
        isAoP1Vault[vault] = true;
        
        emit VaultDeployed(_name, vault, "AoP1Vault");
        return vault;
    }
    
    /**
     * @dev Deploy a new AoP2Vault
     * @param _name Name of the vault
     * @param _symbol Symbol of the vault
     * @return Address of the deployed vault
     */
    function deployAoP2Vault(string memory _name, string memory _symbol) external onlyOwner returns (address) {
        require(vaults[_name] == address(0), "Vault with this name already exists");
        
        address vault = AoP2VaultHelpers.deployVault(
            _name,
            _symbol,
            usdtToken,
            defaultFeeRecipient,
            pythContract,
            monUsdPriceId
        );
        
        vaults[_name] = vault;
        
        emit VaultDeployed(_name, vault, "AoP2Vault");
        return vault;
    }
    
    /**
     * @dev Add an agent to a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to add
     */
    function addAgentToVault(address vaultAddress, address agent) external onlyOwner {
        require(vaultAddress != address(0), "Invalid vault address");
        require(agent != address(0), "Invalid agent address");
        
        VaultHelpers.addAgentToVault(vaultAddress, agent, isAoP1Vault[vaultAddress]);
        emit AgentAdded(vaultAddress, agent);
    }
    
    /**
     * @dev Remove an agent from a vault
     * @param vaultAddress Address of the vault
     * @param agent Address of the agent to remove
     */
    function removeAgentFromVault(address vaultAddress, address agent) external onlyOwner {
        require(vaultAddress != address(0), "Invalid vault address");
        require(agent != address(0), "Invalid agent address");
        
        VaultHelpers.removeAgentFromVault(vaultAddress, agent, isAoP1Vault[vaultAddress]);
        emit AgentRemoved(vaultAddress, agent);
    }
    
    /**
     * @dev Update the fee recipient for a vault
     * @param vaultAddress Address of the vault
     * @param newFeeRecipient New fee recipient
     */
    function updateFeeRecipient(address vaultAddress, address newFeeRecipient) external onlyOwner {
        require(vaultAddress != address(0), "Invalid vault address");
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        
        VaultHelpers.updateFeeRecipient(vaultAddress, newFeeRecipient, isAoP1Vault[vaultAddress]);
        emit FeeRecipientUpdated(newFeeRecipient);
    }
    
    /**
     * @dev Update the default fee recipient for new vaults
     * @param newFeeRecipient New default fee recipient
     */
    function updateDefaultFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        defaultFeeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }
    
    /**
     * @dev Get the address of a vault by name
     * @param name Name of the vault
     * @return The address of the vault, or zero address if not found
     */
    function getVaultAddress(string memory name) external view returns (address) {
        return vaults[name];
    }
    
    /**
     * @dev Get user details from a vault
     * @param vaultAddress Address of the vault
     * @param user Address of the user
     * @return shares User's share balance (18 decimals)
     * @return valueInUSDT Value of user's shares in USDT (18 decimals)
     * @return percentageOfVault User's percentage of the vault (basis points)
     * @return profitSinceDeposit User's profit since deposit (18 decimals)
     * @return initialDepositDate User's initial deposit date
     * @return monDeposited Amount of MON deposited (18 decimals, 0 for AoP2Vault)
     * @return usdtDeposited Amount of USDT deposited (6 decimals)
     */
    function getUserDetails(address vaultAddress, address user) external view returns (
        uint256 shares,
        uint256 valueInUSDT,
        uint256 percentageOfVault,
        uint256 profitSinceDeposit,
        uint256 initialDepositDate,
        uint256 monDeposited,
        uint256 usdtDeposited
    ) {
        require(vaultAddress != address(0), "Invalid vault address");
        
        if (isAoP1Vault[vaultAddress]) {
            return AoP1VaultHelpers.getUserDetails(vaultAddress, user);
        } else {
            // For AoP2Vault, monDeposited will always be 0
            (shares, valueInUSDT, percentageOfVault, profitSinceDeposit, initialDepositDate, usdtDeposited) = 
                AoP2VaultHelpers.getUserDetails(vaultAddress, user);
            monDeposited = 0;
        }
    }
    
    /**
     * @dev Get statistics from a vault
     * @param vaultAddress Address of the vault
     * @return totalAssets Total assets in the vault (6 decimals)
     * @return sharePrice Current share price (18 decimals)
     * @return totalShares Total shares issued (18 decimals)
     * @return monBalance MON balance in the vault (18 decimals, 0 for AoP2Vault)
     * @return usdtBalance USDT balance in the vault (6 decimals)
     * @return lastUpdateTime Last update time of the vault
     * @return userCount Number of active users in the vault
     */
    function getVaultStatistics(address vaultAddress) external view returns (
        uint256 totalAssets,
        uint256 sharePrice,
        uint256 totalShares,
        uint256 monBalance,
        uint256 usdtBalance,
        uint256 lastUpdateTime,
        uint256 userCount
    ) {
        require(vaultAddress != address(0), "Invalid vault address");
        
        if (isAoP1Vault[vaultAddress]) {
            return AoP1VaultHelpers.getVaultStatistics(vaultAddress);
        } else {
            // For AoP2Vault, monBalance will always be 0
            (totalAssets, sharePrice, totalShares, usdtBalance, lastUpdateTime, userCount) = 
                AoP2VaultHelpers.getVaultStatistics(vaultAddress);
            monBalance = 0;
        }
    }
    
    /**
     * @dev Get historical NAV data from a vault
     * @param vaultAddress Address of the vault
     * @return timestamps Array of timestamps
     * @return values Array of NAV values (18 decimals)
     * @return totalValues Array of total vault values (6 decimals)
     */
    function getHistoricalNAV(address vaultAddress) external view returns (
        uint256[] memory timestamps,
        uint256[] memory values,
        uint256[] memory totalValues
    ) {
        require(vaultAddress != address(0), "Invalid vault address");
        return VaultHelpers.getHistoricalNAV(vaultAddress, isAoP1Vault[vaultAddress]);
    }
    
    /**
     * @dev Update the Pyth Network contract address
     * @param _pythContract New Pyth Network contract address
     */
    function setPythContract(address _pythContract) external onlyOwner {
        require(_pythContract != address(0), "Pyth contract cannot be zero");
        pythContract = _pythContract;
        emit PythContractUpdated(_pythContract);
    }
    
    /**
     * @dev Update the MON/USD price feed ID
     * @param _monUsdPriceId New price feed ID
     */
    function setMonUsdPriceId(bytes32 _monUsdPriceId) external onlyOwner {
        monUsdPriceId = _monUsdPriceId;
        emit MonUsdPriceIdUpdated(_monUsdPriceId);
    }
}
