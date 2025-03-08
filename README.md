# Agents of Profits (AoP) Vault Contracts

Smart contracts for the Agents of Profits (AoP) platform on Monad, featuring proportional ownership vaults with real-time price feeds.

## Overview

This repository contains the smart contracts for the AoP platform, which allows users to deposit USDT and MON tokens into vaults. The vaults implement a proportional ownership model with continuous share formulas for fair pricing and profit distribution.

The key components include:
- AoP1Vault: First-generation vault with real-time price feeds from Pyth Network
- AoP2Vault: Second-generation vault with additional features and optimizations
- VaultFactory: Contract for deploying and managing vault instances

## Deployment Information

### Monad Testnet (March 8, 2025)

**Libraries:**
- AoP1VaultHelpers: `0x4059D79249Fa0c984D0F91Cc60aE37E2F085a29d`
- AoP2VaultHelpers: `0xF77d998d2721731E5dDb21fa4701e892feDff1C5`
- VaultHelpers: `0x346d7627d5e1c684337a197A3CA957402861196B`

**Factory and Vaults:**
- VaultFactory: `0x99abDc1fe920cd2525a14ca7764C3F6278200267`
- AoP1Vault: `0xa2B8E2eeef0551f07E7e494517317fe4Aabfc67F`
- AoP2Vault: `0xbB171f61038c9011802a60955e57278C8C5fF80f`

**Configuration:**
- USDT Token: `0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D`
- Fee Recipient: `0x20058C377061C2508047aD07AddF8a55606550FF`
- Pyth Contract: `0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5`
- MON/USD Price Feed ID: `0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b`

## Key Features

- Proportional ownership model based on USDT value
- Continuous share formula for fair pricing
- Real-time NAV updates reflecting MON price changes
- Proper handling of price volatility with 60-second staleness threshold
- Fair profit distribution to all shareholders
- Equivalent share issuance for equal-value deposits regardless of asset

## Development Setup

### Prerequisites

- Node.js v16+ and npm
- Hardhat

### Installation

```bash
npm install
```

### Compilation

```bash
npx hardhat compile
```

### Testing

```bash
npx hardhat test
```

### Deployment

```bash
npx hardhat run scripts/deploy-factory.js --network monadTestnet
```

### Price Update

To update the MON/USD price in the vaults:

```bash
npx hardhat run scripts/update-aop1-price.js --network monadTestnet
```

## Architecture

The contracts implement a proportional ownership model where each user owns a percentage of the vault proportional to their contribution relative to the total value of the vault. This model ensures fair profit distribution and handles the volatility of MON price by using real-time price feeds from Pyth Network.

## Security Considerations

- The contracts use OpenZeppelin's ReentrancyGuard to prevent reentrancy attacks
- Role-based access control using OpenZeppelin's AccessControl
- Price staleness checks to prevent using outdated price information

## License

This project is licensed under the MIT License - see the LICENSE file for details.
