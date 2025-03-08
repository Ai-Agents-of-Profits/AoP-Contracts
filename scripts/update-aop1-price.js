const { ethers } = require("hardhat");
const axios = require("axios");
const fs = require("fs");

// Configuration - adjust as needed
const AOP1_VAULT_ADDRESS = "0xa2B8E2eeef0551f07E7e494517317fe4Aabfc67F"; // Latest deployed AoP1Vault
const MON_USD_PRICE_ID = "0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b";
const PYTH_ADDRESS = "0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5";

// Sample VAA data in case the API call fails
const FALLBACK_UPDATE_DATA = [
  "0x504e41550100000000a0010000000001004770e489489f1bd6dcd1448e051637959b6156194c279ce18c03636a643db52473f16147f4cf66429244524bd080465162c07344cd11e06973ada09244a902060167cba6c800000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000781e8df014155575600000000000c172f3600002710d7ce17197d46e116d034623f0062e7d9167ec23901005500e786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b000000008398612a000000000d28d684fffffff80000000067cba6c80000000067cba6c8000000008394d7f6000000000d287bff0c0f446477187170e577ba8af2efc4511fae3db898b86c3ad6b9cc5e14906444024c9a8521ac179fce3ab7037086a00c9b609cc65291d949e2bd05a5bf738bbcc84f950eb068f22c24dae37d6d1afc629a6832c33e8f0d6cd1e8f3f62cc33b4f0390136a15a5a0039e1a02e63372ea2b6b230fcdcd37c0be86d2216c7c18618ed7cae7a8a54bcb8623bda98b88421d1d8a2c9545c76658a2d3190134d765e4747ee40af4285c1f3af6faedd16ae62dd8b913a436b35a833209e5ff89933273c0a1a7b61d25c65f07e0839722133a8fdc9831a83873142c32f1644657d82c1d1c4a57914151179eb81df13591437ecaec60"
];

// Helper function to format numbers with price exponent
function formatPriceWithExpo(price, expo) {
  return (Number(price) * Math.pow(10, Number(expo))).toFixed(Math.abs(Number(expo)));
}

// Get price updates from Pyth Network
async function getPythPriceUpdates(priceId) {
  try {
    const url = `https://hermes-beta.pyth.network/v2/updates/price/latest?ids[]=${priceId}&encoding=hex`;
    console.log(`Fetching price updates from: ${url}`);
    
    const response = await axios.get(url);
    
    if (response.data && response.data.binary && response.data.binary.data) {
      console.log("Price update data received");
      
      // Log parsed data if available
      if (response.data.parsed && response.data.parsed.length > 0) {
        const priceData = response.data.parsed[0].price;
        console.log("Price information:");
        console.log(`- Price: ${priceData.price}`);
        console.log(`- Confidence: ${priceData.conf}`);
        console.log(`- Exponent: ${priceData.expo}`);
        console.log(`- Publish time: ${new Date(priceData.publish_time * 1000).toISOString()}`);
        console.log(`- Actual price: $${formatPriceWithExpo(priceData.price, priceData.expo)}`);
      }
      
      // Add 0x prefix
      return response.data.binary.data.map(data => `0x${data}`);
    } 
    
    throw new Error("Invalid response format from Pyth Network");
  } catch (error) {
    console.error("Error fetching price updates:", error.message);
    throw error;
  }
}

async function main() {
  try {
    console.log(`Starting AoP1Vault price update process at ${new Date().toISOString()}`);
    
    // Load signer
    const [deployer] = await ethers.getSigners();
    console.log(`Using account: ${deployer.address}`);
    
    // Connect to the AoP1Vault contract
    console.log(`Connecting to AoP1Vault at: ${AOP1_VAULT_ADDRESS}`);
    const AoP1Vault = await ethers.getContractFactory("AoP1Vault");
    const vault = await AoP1Vault.attach(AOP1_VAULT_ADDRESS);
    
    // Get update data
    console.log("Fetching latest price data from Pyth Network...");
    let updateData;
    try {
      updateData = await getPythPriceUpdates(MON_USD_PRICE_ID);
      console.log(`Received ${updateData.length} price update(s) from API`);
    } catch (error) {
      console.warn("Could not fetch price update data from API, using fallback data");
      updateData = FALLBACK_UPDATE_DATA.map(data => data.startsWith('0x') ? data : `0x${data}`);
    }
    
    // Connect to the Pyth contract to get update fee
    console.log(`Connecting to Pyth at: ${PYTH_ADDRESS}`);
    const IPyth = await ethers.getContractAt("IPyth", PYTH_ADDRESS);
    
    // Get update fee
    console.log("Calculating update fee...");
    let updateFee;
    try {
      updateFee = await IPyth.getUpdateFee(updateData);
      console.log(`Update fee: ${ethers.formatEther(updateFee)} MON`);
    } catch (error) {
      console.error("Error getting update fee:", error.message);
      updateFee = ethers.parseEther("0.0001");
      console.log(`Using fallback fee: ${ethers.formatEther(updateFee)} MON`);
    }
    
    // Check if we need to update NAV first
    try {
      const lastNavUpdate = await vault.lastNavUpdate();
      const currentTime = Math.floor(Date.now() / 1000);
      const timeSinceLastUpdate = currentTime - Number(lastNavUpdate);
      console.log(`Time since last NAV update: ${timeSinceLastUpdate} seconds`);
    } catch (error) {
      console.log("Could not check last NAV update time:", error.message);
    }
    
    // Update price on the contract via getMonUsdPrice
    console.log("Updating price on contract...");
    try {
      // We'll call convertMonToUsdt with a small amount to trigger a price update
      const monAmount = ethers.parseEther("0.0001"); // A small amount for testing
      const updateTx = await vault.convertMonToUsdt(monAmount, updateData, { value: updateFee });
      console.log(`Transaction sent: ${updateTx.hash}`);
      
      const receipt = await updateTx.wait();
      console.log(`Price updated in transaction: ${receipt.hash}`);
      
      console.log("Price update completed successfully!");
    } catch (error) {
      console.error("Error updating price:", error);
      if (error.data) {
        console.error("Error data:", error.data);
      }
    }

    // Use view function to check the current price without updating
    try {
      console.log("\nChecking current price view from contract...");
      const monAmount = ethers.parseEther("1"); // 1 MON for easier reading
      const usdtValue = await vault.convertMonToUsdtView(monAmount);
      console.log(`Current price view: 1 MON = ${ethers.formatUnits(usdtValue, 6)} USDT`);
      
      // Calculate approximate NAV
      try {
        const navPerShare = await vault.navPerShare();
        console.log(`Current NAV per share: ${ethers.formatUnits(navPerShare, 18)}`);
      } catch (error) {
        console.log("Could not fetch NAV per share:", error.message);
      }
    } catch (error) {
      console.error("Error checking current price view:", error.message);
    }
  } catch (error) {
    console.error("Error in main function:", error);
  }
}

// Run the script
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("Unhandled error:", error);
    process.exit(1);
  });
