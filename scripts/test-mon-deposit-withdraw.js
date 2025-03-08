const { ethers } = require("hardhat");

// ABI for AoP1Vault contract functions we need
const AOP1_VAULT_ABI = [
  "function depositMON(bytes[] calldata priceUpdateData) external payable returns (uint256)",
  "function balanceOf(address account) external view returns (uint256)",
  "function withdraw(uint256 shares, bool asUSDT, bytes[] calldata priceUpdateData) external returns (uint256)",
  "function navPerShare() external view returns (uint256)",
  "function getPricePerShare() external view returns (uint256)",
  "function getTotalValueInUsdt(bytes[] calldata priceUpdateData) external returns (uint256)",
  "function totalMonValue() external view returns (uint256)",
  "function estimateSharesForMonDeposit(uint256 monAmount, bytes[] calldata priceUpdateData) external returns (uint256)"
];

async function main() {
  try {
    // Get signer
    const [deployer] = await ethers.getSigners();
    console.log(`Using account: ${deployer.address}`);
    
    // Connect to the deployed AoP1Vault
    const vaultAddress = "0x9b9E48cD1bA058aE4d8579e935bf278dd337Eb40";
    const vault = new ethers.Contract(vaultAddress, AOP1_VAULT_ABI, deployer);
    
    console.log(`Connected to AoP1Vault at ${vaultAddress}`);
    
    // Check initial balances
    const provider = ethers.provider;
    const initialBalance = await provider.getBalance(deployer.address);
    const initialShares = await vault.balanceOf(deployer.address);
    
    console.log(`Initial MON balance: ${ethers.formatEther(initialBalance)} MON`);
    console.log(`Initial shares: ${ethers.formatEther(initialShares)}`);
    
    // Get current NAV
    const initialNav = await vault.navPerShare();
    console.log(`Initial NAV per share: ${ethers.formatUnits(initialNav, 18)}`);
    
    // Estimate shares before deposit
    console.log(`Estimating shares for 1 MON deposit...`);
    const oneEther = ethers.parseEther("1.0");
    
    try {
      const estimatedShares = await vault.estimateSharesForMonDeposit.staticCall(oneEther, []);
      console.log(`Estimated shares: ${ethers.formatEther(estimatedShares)}`);
    } catch (error) {
      console.log("Couldn't estimate shares:", error.message);
    }
    
    // Deposit 1 MON
    console.log(`Depositing 1 MON to the vault...`);
    const depositTx = await vault.depositMON([], { value: oneEther });
    console.log(`Deposit transaction submitted: ${depositTx.hash}`);
    
    const depositReceipt = await depositTx.wait();
    console.log(`Deposit transaction confirmed in block ${depositReceipt.blockNumber}`);
    
    // Check new share balance
    const newShares = await vault.balanceOf(deployer.address);
    console.log(`New shares after deposit: ${ethers.formatEther(newShares)}`);
    
    // Calculate shares received 
    const sharesReceived = newShares - initialShares;
    console.log(`Shares received: ${ethers.formatEther(sharesReceived.toString())}`);
    
    // Get updated NAV
    const afterDepositNav = await vault.navPerShare();
    console.log(`NAV per share after deposit: ${ethers.formatUnits(afterDepositNav, 18)}`);
    
    // Check total vault value
    try {
      const totalValue = await vault.getTotalValueInUsdt.staticCall([]);
      console.log(`Total vault value in USDT: ${ethers.formatUnits(totalValue, 6)}`);
    } catch (error) {
      console.log("Couldn't get total value:", error.message);
    }
    
    // Check MON value in vault
    const monValue = await vault.totalMonValue();
    console.log(`Total MON in vault: ${ethers.formatEther(monValue)}`);
    
    // Wait a bit before withdrawing
    console.log("Waiting 5 seconds before withdrawal...");
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    // Withdraw all shares
    console.log(`Withdrawing all shares as MON...`);
    const withdrawTx = await vault.withdraw(newShares, false, []);
    console.log(`Withdrawal transaction submitted: ${withdrawTx.hash}`);
    
    const withdrawReceipt = await withdrawTx.wait();
    console.log(`Withdrawal transaction confirmed in block ${withdrawReceipt.blockNumber}`);
    
    // Check final balances
    const finalBalance = await provider.getBalance(deployer.address);
    const finalShares = await vault.balanceOf(deployer.address);
    
    console.log(`Final MON balance: ${ethers.formatEther(finalBalance)} MON`);
    console.log(`Final shares: ${ethers.formatEther(finalShares)}`);
    
    // Calculate balance difference (minus gas costs)
    const balanceDiff = finalBalance - initialBalance;
    console.log(`MON difference: ${ethers.formatEther(balanceDiff.toString())} (includes gas costs)`);
    
    console.log("Test completed successfully!");
  } catch (error) {
    console.error("Error during test:", error);
    if (error.data) {
      console.error("Error data:", error.data);
    }
    if (error.transaction) {
      console.error("Error transaction:", error.transaction);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
