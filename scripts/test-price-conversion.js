const { ethers } = require("hardhat");

async function main() {
  // Get the latest deployment info
  const vaultAddress = "0xa2B8E2eeef0551f07E7e494517317fe4Aabfc67F";
  const pythAddress = "0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5";
  const priceId = "0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b";
  
  console.log("Testing price conversion for AoP1Vault");
  console.log("Vault address:", vaultAddress);
  
  // Connect to contracts
  const [signer] = await ethers.getSigners();
  console.log("Using account:", signer.address);
  
  const vault = await ethers.getContractAt("AoP1Vault", vaultAddress);
  const pyth = await ethers.getContractAt("IPyth", pythAddress);
  
  // 1. Call the Pyth contract directly to get the raw price
  try {
    console.log("\n1. Getting raw price data from Pyth:");
    const priceData = await pyth.getPriceUnsafe(priceId);
    console.log("- Raw price:", priceData.price.toString());
    console.log("- Confidence:", priceData.conf.toString());
    console.log("- Expo:", priceData.expo.toString());
    console.log("- Publish time:", new Date(Number(priceData.publishTime) * 1000).toISOString());
    
    // Calculate the actual price based on exponent
    const actualPrice = Number(priceData.price) * 10 ** Number(priceData.expo);
    console.log("- Actual price (calculated):", actualPrice.toFixed(8), "USD");
    
    // Calculate what the price should be with 6 decimals (USDT precision)
    const expectedUsdtPrice = Number(priceData.price) * 10 ** (Number(priceData.expo) + 6);
    console.log("- Expected USDT price (6 decimals):", expectedUsdtPrice.toFixed(0));
  } catch (error) {
    console.error("Error getting price data from Pyth:", error.message);
  }
  
  // 2. View the price from the vault
  try {
    console.log("\n2. Getting price from vault via view function:");
    const viewPrice = await vault.getMonUsdPriceView();
    console.log("- Raw price from vault:", viewPrice.toString());
    
    // Convert 1 MON to USDT for comparison
    const oneMon = ethers.parseEther("1");
    const usdtValue = await vault.convertMonToUsdtView(oneMon);
    console.log("- 1 MON = ", ethers.formatUnits(usdtValue, 6), "USDT");
  } catch (error) {
    console.error("Error getting view price from vault:", error.message);
  }
  
  // 3. Manually perform calculations to understand the issue
  console.log("\n3. Manual debugging calculations:");
  try {
    const priceData = await pyth.getPriceUnsafe(priceId);
    console.log("- Raw price:", priceData.price.toString());
    console.log("- Expo:", priceData.expo.toString());
    
    // Expected calculations for 6 decimals
    const expoAdjustment = 6 + Number(priceData.expo);
    console.log("- Expo adjustment (6 + price.expo):", expoAdjustment);
    
    if (expoAdjustment > 0) {
      let scaleFactor = 1;
      for (let i = 0; i < expoAdjustment && i < 59; i++) {
        scaleFactor *= 10;
      }
      console.log("- Scale factor calculated:", scaleFactor);
      
      const safePrice = BigInt(priceData.price) * BigInt(scaleFactor);
      console.log("- Scaled price:", safePrice.toString());
      
      // Calculate final USDT value for 1 MON with proper scaling
      const oneMon = ethers.parseEther("1"); // 1 MON (18 decimals)
      console.log("- 1 MON in wei:", oneMon.toString());
      
      const manuallyCalculatedValue = (BigInt(oneMon) * BigInt(safePrice)) / BigInt(10n ** 6n);
      console.log("- Manual calculation (1 MON to USDT):", manuallyCalculatedValue.toString());
      console.log("  Formatted:", ethers.formatUnits(manuallyCalculatedValue, 6), "USDT");
    } else {
      console.log("- Negative expoAdjustment, different calculation path");
    }
  } catch (error) {
    console.error("Error during manual calculations:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Unhandled error:", error);
    process.exit(1);
  });
