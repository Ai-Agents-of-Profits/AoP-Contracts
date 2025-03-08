const { ethers } = require("hardhat");
const fs = require("fs");

// Get deployed contract information
let deploymentInfo;
try {
  deploymentInfo = JSON.parse(fs.readFileSync("./deployment-info.json"));
  console.log("Loaded deployment info from file");
} catch (error) {
  console.error("Could not load deployment info:", error.message);
  console.error("Please run deploy-pyth-test.js first");
  process.exit(1);
}

// Helper function to format numbers with price exponent
function formatPriceWithExpo(price, expo) {
  return (Number(price) * Math.pow(10, Number(expo))).toFixed(Math.abs(Number(expo)));
}

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log(`Using account: ${deployer.address}`);
    
    // Connect to the deployed contract
    const pythPriceTestAddress = deploymentInfo.pythPriceTest;
    console.log(`Connecting to PythPriceTest at: ${pythPriceTestAddress}`);
    
    const PythPriceTest = await ethers.getContractFactory("PythPriceTest");
    const pythPriceTest = await PythPriceTest.attach(pythPriceTestAddress);
    
    // Get the stored price data
    console.log("Reading stored price data from contract...");
    const latestPrice = await pythPriceTest.latestPrice();
    const latestConfidence = await pythPriceTest.latestConfidence();
    const latestExponent = await pythPriceTest.latestExponent();
    const latestPublishTime = await pythPriceTest.latestPublishTime();
    
    console.log("Stored price data in contract:");
    console.log(`- Price: ${latestPrice}`);
    console.log(`- Confidence: ${latestConfidence}`);
    console.log(`- Exponent: ${latestExponent}`);
    console.log(`- Publish time: ${latestPublishTime}`);
    console.log(`- Publish date: ${new Date(Number(latestPublishTime) * 1000).toISOString()}`);
    
    const actualPrice = formatPriceWithExpo(latestPrice, latestExponent);
    console.log(`- Human-readable price: $${actualPrice}`);
    
    // Try getting the price in USD
    try {
      const priceInUsd = await pythPriceTest.getPriceInUsd();
      console.log(`\nFormatted price in USD: ${priceInUsd}`);
    } catch (error) {
      console.error("Error getting price in USD:", error.message);
    }
    
    // Try getting current price from Pyth directly
    console.log("\nAttempting to get current price directly from Pyth Network...");
    try {
      const currentPrice = await pythPriceTest.getCurrentPriceFromPyth();
      console.log("Current price data from Pyth:");
      console.log(`- Price: ${currentPrice[0]}`);
      console.log(`- Confidence: ${currentPrice[1]}`);
      console.log(`- Exponent: ${currentPrice[2]}`);
      console.log(`- Publish time: ${currentPrice[3]}`);
      console.log(`- Publish date: ${new Date(Number(currentPrice[3]) * 1000).toISOString()}`);
      
      const currentActualPrice = formatPriceWithExpo(currentPrice[0], currentPrice[2]);
      console.log(`- Human-readable price: $${currentActualPrice}`);
    } catch (error) {
      console.log("Error getting current price from Pyth:", error.message);
    }
  } catch (error) {
    console.error("Error in main function:", error.message);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Unhandled error:", error.message);
    process.exit(1);
  });
