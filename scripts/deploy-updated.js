// We require the Hardhat Runtime Environment explicitly here.
const hre = require("hardhat");

async function main() {
  console.log("Deploying updated contracts to Monad testnet without price expiry checks...");

  // Use existing USDT token on Monad testnet
  const usdtAddress = "0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D";
  console.log("Using existing USDT at:", usdtAddress);

  // Set up parameters for deployment
  const feeRecipient = "0x20058C377061C2508047aD07AddF8a55606550FF";
  
  // Pyth contract address on Monad testnet
  const pythContract = "0xad2B52D2af1a9bD5c561894Cdd84f7505e1CD0B5";
  
  // Price feed ID for MON/USD 
  const monUsdPriceId = "0xe786153cc54abd4b0e53b4c246d54d9f8eb3f3b5a34d4fc5a2e9a423b0ba5d6b";
  
  // Deploy all helper libraries first
  console.log("\n1. Deploying libraries...");
  
  // Deploy AoP1VaultHelpers (with optimization to handle circular dependencies)
  const AoP1VaultHelpers = await hre.ethers.getContractFactory("AoP1VaultHelpers");
  const aop1VaultHelpers = await AoP1VaultHelpers.deploy();
  await aop1VaultHelpers.waitForDeployment();
  const aop1VaultHelpersAddress = await aop1VaultHelpers.getAddress();
  console.log("AoP1VaultHelpers deployed to:", aop1VaultHelpersAddress);

  // Deploy AoP2VaultHelpers
  const AoP2VaultHelpers = await hre.ethers.getContractFactory("AoP2VaultHelpers");
  const aop2VaultHelpers = await AoP2VaultHelpers.deploy();
  await aop2VaultHelpers.waitForDeployment();
  const aop2VaultHelpersAddress = await aop2VaultHelpers.getAddress();
  console.log("AoP2VaultHelpers deployed to:", aop2VaultHelpersAddress);

  // Deploy VaultHelpers with the library links
  const vaultHelpersLibraries = {
    "contracts/libraries/AoP1VaultHelpers.sol:AoP1VaultHelpers": aop1VaultHelpersAddress,
    "contracts/libraries/AoP2VaultHelpers.sol:AoP2VaultHelpers": aop2VaultHelpersAddress
  };
  
  const VaultHelpers = await hre.ethers.getContractFactory("VaultHelpers", {
    libraries: vaultHelpersLibraries
  });
  
  const vaultHelpers = await VaultHelpers.deploy();
  await vaultHelpers.waitForDeployment();
  const vaultHelpersAddress = await vaultHelpers.getAddress();
  console.log("VaultHelpers deployed to:", vaultHelpersAddress);

  // Now deploy the VaultFactory with all libraries linked
  console.log("\n2. Deploying VaultFactory...");
  
  const factoryLibraries = {
    "contracts/libraries/AoP1VaultHelpers.sol:AoP1VaultHelpers": aop1VaultHelpersAddress,
    "contracts/libraries/AoP2VaultHelpers.sol:AoP2VaultHelpers": aop2VaultHelpersAddress,
    "contracts/libraries/VaultHelpers.sol:VaultHelpers": vaultHelpersAddress
  };
  
  const VaultFactory = await hre.ethers.getContractFactory("VaultFactory", {
    libraries: factoryLibraries
  });
  
  const vaultFactory = await VaultFactory.deploy(
    usdtAddress,            // USDT token address
    feeRecipient,           // Fee recipient
    pythContract,           // Pyth contract address
    monUsdPriceId           // MON/USD price feed ID
  );
  
  await vaultFactory.waitForDeployment();
  const vaultFactoryAddress = await vaultFactory.getAddress();
  console.log("VaultFactory deployed to:", vaultFactoryAddress);

  // Deploy AoP1Vault directly
  console.log("\n3. Deploying AoP1Vault directly...");
  
  const AoP1Vault = await hre.ethers.getContractFactory("AoP1Vault");
  const aop1Vault = await AoP1Vault.deploy(
    "Agent of Profits Vault 1",  // name
    "AOP1",                      // symbol
    usdtAddress,                 // USDT token address
    feeRecipient,                // Fee recipient
    pythContract,                // Pyth contract address
    monUsdPriceId                // MON/USD price feed ID
  );

  await aop1Vault.waitForDeployment();
  const aop1VaultAddress = await aop1Vault.getAddress();
  console.log("AoP1Vault deployed to:", aop1VaultAddress);

  // Deploy AoP1Vault and AoP2Vault through the factory as well
  console.log("\n4. Deploying vaults via factory...");
  const tx1 = await vaultFactory.deployAoP1Vault("Agent of Profits Factory Vault 1", "AOPF1");
  await tx1.wait();
  
  const tx2 = await vaultFactory.deployAoP2Vault("Agent of Profits Factory Vault 2", "AOPF2");
  await tx2.wait();
  
  // Get deployed vault addresses from factory
  const aopf1VaultAddress = await vaultFactory.vaults("Agent of Profits Factory Vault 1");
  const aopf2VaultAddress = await vaultFactory.vaults("Agent of Profits Factory Vault 2");
  
  console.log("AoP1Vault deployed via factory to:", aopf1VaultAddress);
  console.log("AoP2Vault deployed via factory to:", aopf2VaultAddress);

  // Output comprehensive deployment summary
  console.log("\nDeployment Summary:");
  console.log("===================");
  console.log("Libraries:");
  console.log("- AoP1VaultHelpers:", aop1VaultHelpersAddress);
  console.log("- AoP2VaultHelpers:", aop2VaultHelpersAddress);
  console.log("- VaultHelpers:", vaultHelpersAddress);
  console.log("\nFactory:");
  console.log("- VaultFactory:", vaultFactoryAddress);
  console.log("\nVaults:");
  console.log("- AoP1Vault (Direct):", aop1VaultAddress);
  console.log("- AoP1Vault (Factory):", aopf1VaultAddress);
  console.log("- AoP2Vault (Factory):", aopf2VaultAddress);
  console.log("\nConfiguration:");
  console.log("- USDT Token:", usdtAddress);
  console.log("- Fee Recipient:", feeRecipient);
  console.log("- Pyth Contract:", pythContract);
  console.log("- MON/USD Price Feed ID:", monUsdPriceId);
  console.log("- No Price Expiry Check: Staleness checks removed as requested");
  
  console.log("\nNext steps:");
  console.log("1. Send some USDT to the vaults to initialize them");
  console.log("2. Add agents to the vaults through the factory");
  console.log("3. Test deposits and withdrawals with real-time price feeds");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
