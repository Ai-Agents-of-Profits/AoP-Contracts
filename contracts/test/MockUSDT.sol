// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockUSDT
 * @dev A mock USDT token for testing purposes
 * @notice This contract is only for testing and not meant for production use
 */
contract MockUSDT is ERC20 {
    uint8 private _decimals = 6; // USDT has 6 decimals
    
    constructor() ERC20("Mock USDT", "mUSDT") {
        // Mint 1 million USDT (with 6 decimals) to the deployer
        _mint(msg.sender, 1000000 * 10**6);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
