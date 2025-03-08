// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PythPriceTest
 * @dev A test contract for interacting with Pyth Network price feeds
 */
contract PythPriceTest {
    IPyth public pyth;
    bytes32 public priceId;
    uint256 public priceExpirySeconds;
    
    // Store latest price received
    int64 public latestPrice;
    uint64 public latestConfidence;
    int32 public latestExponent;
    uint256 public latestPublishTime;
    
    // Track actions in events
    event PriceUpdated(int64 price, uint64 confidence, int32 exponent, uint256 publishTime);
    event ActionPerformed(string action, uint256 value, int64 price);
    
    // Errors
    error StalePrice(uint256 publishTime, uint256 currentTime);
    error PriceTooLow(int64 price, int64 minPrice);
    error InvalidAmount();
    
    /**
     * @dev Constructor to set up the Pyth price feed connection
     * @param _pythAddress Address of the Pyth Network contract
     * @param _priceId The price feed ID to use (e.g., MON/USD)
     * @param _priceExpirySeconds Number of seconds after which a price is considered stale
     */
    constructor(address _pythAddress, bytes32 _priceId, uint256 _priceExpirySeconds) {
        pyth = IPyth(_pythAddress);
        priceId = _priceId;
        priceExpirySeconds = _priceExpirySeconds;
    }
    
    /**
     * @dev Updates the price feed data from Pyth
     * @param updateData The encoded price update data from Pyth
     */
    function updatePrice(bytes[] calldata updateData) external payable {
        // Check the fee required for the update
        uint256 fee = pyth.getUpdateFee(updateData);
        
        // Update price feeds
        pyth.updatePriceFeeds{value: fee}(updateData);
        
        // Get updated price
        PythStructs.Price memory priceData = pyth.getPriceNoOlderThan(priceId, 0);
        
        // Store the updated price info
        latestPrice = priceData.price;
        latestConfidence = priceData.conf;
        latestExponent = priceData.expo;
        latestPublishTime = priceData.publishTime;
        
        // Emit event
        emit PriceUpdated(latestPrice, latestConfidence, latestExponent, latestPublishTime);
    }

    /**
     * @dev Updates the price data using updateData and ignores staleness
     * @param updateData The encoded price update data from Pyth
     */
    function updatePriceUnsafe(bytes[] calldata updateData) external payable {
        // Check the fee required for the update
        uint256 fee = pyth.getUpdateFee(updateData);
        
        // Update price feeds
        pyth.updatePriceFeeds{value: fee}(updateData);
        
        // Get updated price without checking freshness
        PythStructs.Price memory priceData = pyth.getPriceUnsafe(priceId);
        
        // Store the updated price info
        latestPrice = priceData.price;
        latestConfidence = priceData.conf;
        latestExponent = priceData.expo;
        latestPublishTime = priceData.publishTime;
        
        // Emit event
        emit PriceUpdated(latestPrice, latestConfidence, latestExponent, latestPublishTime);
    }
    
    /**
     * @dev Performs an action that requires a fresh price
     * @param minPrice The minimum acceptable price for the action
     * @return The price used for the action
     */
    function performAction(int64 minPrice) external payable returns (int64) {
        if (msg.value == 0) revert InvalidAmount();
        
        // Check if price is fresh
        if (block.timestamp > latestPublishTime + priceExpirySeconds) {
            revert StalePrice(latestPublishTime, block.timestamp);
        }
        
        // Check if price meets minimum threshold
        if (latestPrice < minPrice) {
            revert PriceTooLow(latestPrice, minPrice);
        }
        
        // Perform some action based on the price
        emit ActionPerformed("deposit", msg.value, latestPrice);
        
        return latestPrice;
    }
    
    /**
     * @dev Updates the price and performs an action in a single transaction
     * @param updateData The encoded price update data from Pyth
     * @param minPrice The minimum acceptable price for the action
     * @return The price used for the action
     */
    function updateAndPerformAction(bytes[] calldata updateData, int64 minPrice) external payable returns (int64) {
        if (msg.value == 0) revert InvalidAmount();
        
        // Calculate Pyth update fee
        uint256 fee = pyth.getUpdateFee(updateData);
        
        // Make sure there's enough value provided
        require(msg.value > fee, "Insufficient funds for update fee");
        
        // Update price feeds
        pyth.updatePriceFeeds{value: fee}(updateData);
        
        // Get updated price
        PythStructs.Price memory priceData = pyth.getPriceNoOlderThan(priceId, 0);
        
        // Store the updated price info
        latestPrice = priceData.price;
        latestConfidence = priceData.conf;
        latestExponent = priceData.expo;
        latestPublishTime = priceData.publishTime;
        
        // Check if price meets minimum threshold
        if (latestPrice < minPrice) {
            revert PriceTooLow(latestPrice, minPrice);
        }
        
        // Perform some action based on the price
        uint256 actionValue = msg.value - fee;
        emit ActionPerformed("deposit", actionValue, latestPrice);
        
        return latestPrice;
    }
    
    /**
     * @dev Gets the current price data from Pyth directly
     * @return price The current price
     * @return conf The confidence interval
     * @return expo The price exponent
     * @return publishTime The publish time of the price
     */
    function getCurrentPriceFromPyth() external view returns (int64 price, uint64 conf, int32 expo, uint256 publishTime) {
        try pyth.getPriceUnsafe(priceId) returns (PythStructs.Price memory priceData) {
            return (priceData.price, priceData.conf, priceData.expo, priceData.publishTime);
        } catch {
            return (0, 0, 0, 0);
        }
    }
    
    /**
     * @dev Converts price to a human-readable format
     * @return The price in human-readable format
     */
    function getPriceInUsd() external view returns (int256) {
        // Convert the exponent to a uint for exponentiation, then apply the sign after
        int256 exponent = int256(latestExponent);
        uint256 absExponent = exponent < 0 ? uint256(-exponent) : uint256(exponent);
        
        if (exponent >= 0) {
            return int256(latestPrice) * int256(10 ** absExponent);
        } else {
            // Handle negative exponent by dividing
            return int256(latestPrice) / int256(10 ** absExponent);
        }
    }
    
    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}
}
