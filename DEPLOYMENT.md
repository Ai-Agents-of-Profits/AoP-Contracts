# Agent of Profits (AoP) Contract Deployment Guide

This document outlines the recommended deployment order for the Agent of Profits smart contract system on the Monad Testnet.

## Prerequisites

Before deploying the contracts, ensure you have:

1. A wallet with sufficient MON tokens for gas fees on Monad Testnet
2. Access to a Monad Testnet RPC endpoint (https://testnet-rpc.monad.xyz/)
3. Environment variables configured in `.env` file with:
   - `PRIVATE_KEY`: Your deployment wallet's private key
   - `MONAD_TESTNET_RPC`: The Monad Testnet RPC URL

## Contract Deployment Order

The deployment should follow this specific order to ensure all dependencies are properly set up:

### 1. Deploy Library Contracts

Libraries must be deployed first since they don't have external dependencies and are required by other contracts.

```bash
# 1. Deploy VaultHelpers library
npx hardhat deploy --tags VaultHelpers --network monad-testnet

# 2. Deploy AoP1VaultHelpers library
npx hardhat deploy --tags AoP1VaultHelpers --network monad-testnet

# 3. Deploy AoP2VaultHelpers library
npx hardhat deploy --tags AoP2VaultHelpers --network monad-testnet
```

*Note: After deploying each library, you'll need to add their addresses to your deployment script or configuration for linking with the main contracts.*

### 2. Deploy VaultFactory Contract

The VaultFactory depends on the helper libraries and must be deployed after them.

```bash
# Deploy VaultFactory with library addresses
npx hardhat deploy --tags VaultFactory --network monad-testnet
```

### 3. Create Vaults Using the Factory

Once the VaultFactory is deployed, you can create vaults through it rather than deploying vault contracts directly.

#### Creating an AoP1Vault (Medium Risk - MON+USDT)

```javascript
// Example deployment parameters
const vaultName = "AoP Medium Risk Vault";
const vaultSymbol = "AOP1";
const usdtTokenAddress = "0x1E4A5963aBFD975d8c9021ce480b42188849D41d"; // Monad Testnet USDT
const feeRecipient = "YOUR_FEE_RECIPIENT_ADDRESS";

// Create a new AoP1Vault through the factory
await vaultFactory.createAoP1Vault(
  vaultName,
  vaultSymbol,
  usdtTokenAddress,
  feeRecipient
);
```

#### Creating an AoP2Vault (High Risk - USDT-only)

```javascript
// Example deployment parameters
const vaultName = "AoP High Risk Vault";
const vaultSymbol = "AOP2";
const usdtTokenAddress = "0x1E4A5963aBFD975d8c9021ce480b42188849D41d"; // Monad Testnet USDT
const feeRecipient = "YOUR_FEE_RECIPIENT_ADDRESS";

// Create a new AoP2Vault through the factory
await vaultFactory.createAoP2Vault(
  vaultName,
  vaultSymbol,
  usdtTokenAddress,
  feeRecipient
);
```

## Post-Deployment Configuration

After deploying the contracts, perform these additional steps:

1. **Add Agents to Vaults**:
   ```javascript
   // Add an agent to a vault
   await vaultFactory.addAgentToVault(vaultAddress, agentAddress, isAoP1Vault);
   ```

2. **Update Fee Recipient** (if needed):
   ```javascript
   // Update the fee recipient for a vault
   await vaultFactory.updateFeeRecipient(vaultAddress, newFeeRecipient, isAoP1Vault);
   ```

3. **Verify Contracts on Monad Explorer**:
   ```bash
   # Example verification command
   npx hardhat verify --network monad-testnet <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
   ```

## Contract Addresses on Monad Testnet

| Contract | Address |
|----------|---------|
| USDT Token | 0x1E4A5963aBFD975d8c9021ce480b42188849D41d |
| MON Token | 0xBbD3321f377742c4b9825f1a9ac67e9EB999F651 |
| VaultHelpers | TBD after deployment |
| AoP1VaultHelpers | TBD after deployment |
| AoP2VaultHelpers | TBD after deployment |
| VaultFactory | TBD after deployment |

## Important Notes

1. The VaultFactory has admin privileges for all vaults it creates
2. All contracts use Solidity 0.8.20
3. USDT token has 6 decimals, while vault shares use 18 decimals (automatic conversion is handled in the contracts)
4. Oracle integration has been simplified - price conversions now use placeholder methods

## Troubleshooting

If you encounter any issues during deployment:

1. Ensure your wallet has sufficient MON for gas
2. Verify all library addresses are correctly provided to dependent contracts
3. Check that the USDT token address is correct for Monad Testnet
4. Ensure constructor arguments match contract requirements

## Security Considerations

- Transfer ownership of the VaultFactory to a secure multisig wallet after initial setup
- Test deposits and withdrawals with small amounts before allowing significant fund inflows
- Monitor gas costs on Monad Testnet as they may differ from other networks

For any additional support, please refer to the project documentation or contact the development team.
