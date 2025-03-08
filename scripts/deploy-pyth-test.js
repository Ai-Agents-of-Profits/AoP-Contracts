const { ethers } = require("hardhat");

// Constants for Monad testnet
const PYTH_ADDRESS = "0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5";
const MON_USD_PRICE_ID = "0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b";
const PRICE_EXPIRY_SECONDS = 300; // 5 minutes

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log(`Using account: ${deployer.address}`);
    
    // Deploy the PythPriceTest contract
    console.log("Deploying PythPriceTest contract...");
    const PythPriceTestFactory = await ethers.getContractFactory("PythPriceTest");
    const pythPriceTest = await PythPriceTestFactory.deploy(
      PYTH_ADDRESS,
      MON_USD_PRICE_ID,
      PRICE_EXPIRY_SECONDS
    );
    
    await pythPriceTest.waitForDeployment();
    const contractAddress = await pythPriceTest.getAddress();
    console.log(`PythPriceTest deployed to: ${contractAddress}`);
    
    // Try to get current price directly through our contract
    console.log("Getting current price from Pyth via contract...");
    try {
      const currentPrice = await pythPriceTest.getCurrentPriceFromPyth();
      console.log("Current price data:");
      console.log(`- Price: ${currentPrice[0]}`);
      console.log(`- Confidence: ${currentPrice[1]}`);
      console.log(`- Exponent: ${currentPrice[2]}`);
      console.log(`- Publish time: ${currentPrice[3]}`);
      
      if (currentPrice[3].toString() !== "0") {
        const actualPrice = (Number(currentPrice[0]) * Math.pow(10, Number(currentPrice[2]))).toFixed(Math.abs(Number(currentPrice[2])));
        console.log(`- Actual price: $${actualPrice}`);
      } else {
        console.log("Price not yet initialized on Pyth");
      }
    } catch (error) {
      console.error("Error getting current price:", error.message);
    }
    
    // Write deployment info to a file
    const fs = require("fs");
    const deploymentInfo = {
      network: "monadTestnet",
      pythPriceTest: contractAddress,
      pythAddress: PYTH_ADDRESS,
      monUsdPriceId: MON_USD_PRICE_ID,
      deployTime: new Date().toISOString(),
    };
    
    fs.writeFileSync(
      "./deployment-info.json", 
      JSON.stringify(deploymentInfo, null, 2)
    );
    console.log("Deployment info saved to deployment-info.json");
    
  } catch (error) {
    console.error("Error in deployment:", error);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Unhandled error:", error);
    process.exit(1);
  });
