const hre = require("hardhat");

async function main() {
  console.log("Deploying AchievementToken to", hre.network.name, "...\n");

  // Get the deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Check balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "ETH\n");

  if (balance === 0n) {
    console.error("ERROR: Deployer wallet has no ETH!");
    console.error("Get testnet ETH from: https://www.alchemy.com/faucets/base-sepolia");
    process.exit(1);
  }

  // Deploy the contract
  console.log("Deploying AchievementToken...");
  const AchievementToken = await hre.ethers.getContractFactory("AchievementToken");
  const token = await AchievementToken.deploy();

  await token.waitForDeployment();
  const contractAddress = await token.getAddress();

  console.log("\n========================================");
  console.log("SUCCESS! Contract deployed!");
  console.log("========================================\n");
  console.log("Contract Address:", contractAddress);
  console.log("Owner (Minter):", deployer.address);
  console.log("\nView on BaseScan:");

  if (hre.network.name === "baseSepolia") {
    console.log(`https://sepolia.basescan.org/address/${contractAddress}`);
  } else {
    console.log(`https://basescan.org/address/${contractAddress}`);
  }

  console.log("\n========================================");
  console.log("NEXT STEPS - Add to backend/.env:");
  console.log("========================================\n");
  console.log(`CHAIN_ID=84532`);
  console.log(`RPC_URL=https://sepolia.base.org`);
  console.log(`ACHIEVEMENT_CONTRACT_ADDRESS=${contractAddress}`);
  console.log(`MINTER_PRIVATE_KEY=${process.env.DEPLOYER_PRIVATE_KEY}`);
  console.log(`PLATFORM_WALLET_ADDRESS=${deployer.address}`);
  console.log(`PLATFORM_WALLET_KEY=${process.env.DEPLOYER_PRIVATE_KEY}`);
  console.log(`BRIDGE_COOLDOWN_HOURS=0.033`);
  console.log("\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
