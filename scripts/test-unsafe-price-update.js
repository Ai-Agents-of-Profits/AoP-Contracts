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

// Sample VAA data (0x prefix added)
const updateData = [
  "0x504e41550100000000a0010000000001004770e489489f1bd6dcd1448e051637959b6156194c279ce18c03636a643db52473f16147f4cf66429244524bd080465162c07344cd11e06973ada09244a902060167cba6c800000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000781e8df014155575600000000000c172f3600002710d7ce17197d46e116d034623f0062e7d9167ec23901005500e786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b000000008398612a000000000d28d684fffffff80000000067cba6c80000000067cba6c8000000008394d7f6000000000d287bff0c0f446477187170e577ba8af2efc4511fae3db898b86c3ad6b9cc5e14906444024c9a8521ac179fce3ab7037086a00c9b609cc65291d949e2bd05a5bf738bbcc84f950eb068f22c24dae37d6d1afc629a6832c33e8f0d6cd1e8f3f62cc33b4f0390136a15a5a0039e1a02e63372ea2b6b230fcdcd37c0be86d2216c7c18618ed7cae7a8a54bcb8623bda98b88421d1d8a2c9545c76658a2d3190134d765e4747ee40af4285c1f3af6faedd16ae62dd8b913a436b35a833209e5ff89933273c0a1a7b61d25c65f07e0839722133a8fdc9831a83873142c32f1644657d82c1d1c4a57914151179eb81df13591437ecaec60"
];

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log(`Using account: ${deployer.address}`);
    
    // Connect to the deployed contract
    const pythPriceTestAddress = deploymentInfo.pythPriceTest;
    console.log(`Connecting to PythPriceTest at: ${pythPriceTestAddress}`);
    
    const PythPriceTest = await ethers.getContractFactory("PythPriceTest");
    const pythPriceTest = await PythPriceTest.attach(pythPriceTestAddress);
    
    // Set a fixed update fee to avoid any potential issues
    const updateFee = ethers.parseEther("0.0001");
    console.log(`Using update fee: ${ethers.formatEther(updateFee)} MON`);
    
    // Update price using the updatePriceUnsafe method
    console.log("Updating price using updatePriceUnsafe method...");
    try {
      const updateTx = await pythPriceTest.updatePriceUnsafe(updateData, { value: updateFee });
      console.log(`Transaction sent: ${updateTx.hash}`);
      
      console.log("Waiting for transaction confirmation...");
      const receipt = await updateTx.wait();
      console.log(`Price updated successfully in transaction: ${receipt.hash}`);
    } catch (error) {
      console.error("Error updating price:", error.message);
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
