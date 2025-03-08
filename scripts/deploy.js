// We require the Hardhat Runtime Environment explicitly here.
const hre = require("hardhat");

async function main() {
  console.log("Deploying contracts to Monad testnet...");

  // Use existing USDT token on Monad testnet
  const usdtAddress = "0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D";
  console.log("Using existing USDT at:", usdtAddress);

  // Set up parameters for AoP1Vault deployment via VaultFactory
  const feeRecipient = "0x20058C377061C2508047aD07AddF8a55606550FF";
  
  // Pyth contract address on Monad testnet
  const pythContract = "0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5";
  
  // Price feed ID for MON/USD 
  const monUsdPriceId = "0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b";
  
  // Set price expiry to 300 seconds (5 minutes) - reasonable for price feeds
  const pythPriceExpirySeconds = 300;

  // ----- DIRECT DEPLOYMENT APPROACH -----
  // Instead of using libraries and factory, we'll deploy AoP1Vault directly
  
  console.log("Deploying AoP1Vault directly...");
  const AoP1Vault = await hre.ethers.getContractFactory("AoP1Vault");
  const aop1Vault = await AoP1Vault.deploy(
    "Agent of Profits Vault",  // name
    "AOP",                     // symbol
    usdtAddress,               // USDT token address
    feeRecipient,              // Fee recipient
    pythContract,              // Pyth contract address
    monUsdPriceId,             // MON/USD price feed ID
    pythPriceExpirySeconds     // Price expiry in seconds
  );

  await aop1Vault.waitForDeployment();
  const aop1VaultAddress = await aop1Vault.getAddress();
  console.log("AoP1Vault deployed to:", aop1VaultAddress);

  // ----- DEPLOYMENT SUMMARY -----
  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("USDT Address:", usdtAddress);
  console.log("Fee Recipient:", feeRecipient);
  console.log("Pyth Contract:", pythContract);
  console.log("MON/USD Price Feed ID:", monUsdPriceId);
  console.log("Price Expiry Seconds:", pythPriceExpirySeconds);
  console.log("AoP1Vault:", aop1VaultAddress);
  
  console.log("\nNext steps:");
  console.log("1. Send some USDT to the vault to initialize it");
  console.log("2. Use the Pyth Network API to fetch price updates for the MON/USD feed");
  console.log("3. Test vault functionality with the real-time price feed");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
