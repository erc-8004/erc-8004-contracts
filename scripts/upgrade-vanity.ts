import hre from "hardhat";
import { encodeFunctionData, Hex } from "viem";
import dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

/**
 * Expected vanity proxy addresses (deterministic across all networks)
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004A447dc6c917E1bcF82e9a99cfB4fD234CD25",
  reputationRegistry: "0x8004BcCb56C627d615B51b8f85Ef2285E12C482D",
  validationRegistry: "0x8004C6ABFc5d8Eb2cb31AFb47dEb986EdE455f52",
} as const;

/**
 * Implementation addresses (deployed via CREATE2, deterministic across all networks)
 */
const IMPLEMENTATION_ADDRESSES = {
  identityRegistry: "0x4AAC8c0A22a029977Ecc39459DA753e1E5e48315",
  reputationRegistry: "0x29Bd7Cff6C1A31E06b58ad960b1B6c3977DdFA8C",
  validationRegistry: "0xc0dBF87126d203AEa49fbFd59e4DCaBf56608Ce9",
} as const;

/**
 * Upgrade vanity proxies to final implementations
 * This script REQUIRES OWNER_PRIVATE_KEY in .env
 *
 * The owner performs 3 transactions:
 * 1. Upgrade IdentityRegistry proxy
 * 2. Upgrade ReputationRegistry proxy
 * 3. Upgrade ValidationRegistry proxy
 *
 * Each upgrade also initializes the new implementation
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();

  console.log("Upgrading ERC-8004 Vanity Proxies (Owner Phase)");
  console.log("================================================");
  console.log("");

  // Get owner wallet from environment variable
  let ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (!ownerPrivateKey) {
    throw new Error("OWNER_PRIVATE_KEY not found in environment variables. Please add it to .env file.");
  }

  // Ensure private key starts with 0x
  if (!ownerPrivateKey.startsWith("0x")) {
    ownerPrivateKey = `0x${ownerPrivateKey}`;
  }

  // Validate private key format (should be 66 characters: 0x + 64 hex chars)
  if (ownerPrivateKey.length !== 66 || !/^0x[0-9a-fA-F]{64}$/.test(ownerPrivateKey)) {
    throw new Error(`Invalid OWNER_PRIVATE_KEY format. Expected 0x followed by 64 hex characters, got: ${ownerPrivateKey.length} characters`);
  }

  const { createWalletClient, http } = await import("viem");
  const { privateKeyToAccount } = await import("viem/accounts");
  const ownerAccount = privateKeyToAccount(ownerPrivateKey as `0x${string}`);
  const ownerWallet = createWalletClient({
    account: ownerAccount,
    chain: (await viem.getPublicClient()).chain,
    transport: http(),
  });

  console.log("Owner address:", ownerAccount.address);
  console.log("");

  const identityImpl = IMPLEMENTATION_ADDRESSES.identityRegistry as `0x${string}`;
  const reputationImpl = IMPLEMENTATION_ADDRESSES.reputationRegistry as `0x${string}`;
  const validationImpl = IMPLEMENTATION_ADDRESSES.validationRegistry as `0x${string}`;

  console.log("Implementation addresses (deterministic via CREATE2):");
  console.log("  IdentityRegistry:    ", identityImpl);
  console.log("  ReputationRegistry:  ", reputationImpl);
  console.log("  ValidationRegistry:  ", validationImpl);
  console.log("");

  const identityProxyAddress = EXPECTED_ADDRESSES.identityRegistry as `0x${string}`;
  const reputationProxyAddress = EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`;
  const validationProxyAddress = EXPECTED_ADDRESSES.validationRegistry as `0x${string}`;

  console.log("Proxy addresses:");
  console.log("  IdentityRegistry:    ", identityProxyAddress);
  console.log("  ReputationRegistry:  ", reputationProxyAddress);
  console.log("  ValidationRegistry:  ", validationProxyAddress);
  console.log("");

  // Get implementation ABIs
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  console.log("=".repeat(80));
  console.log("PERFORMING UPGRADES");
  console.log("=".repeat(80));
  console.log("");

  // Proxies are already initialized by MinimalUUPS
  // Just upgrade them to real implementations (no need to reinitialize)

  // Helper function to get current implementation
  const getImplementation = async (proxyAddress: `0x${string}`) => {
    const implSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
    return await publicClient.getStorageAt({
      address: proxyAddress,
      slot: implSlot as `0x${string}`,
    });
  };

  // Upgrade IdentityRegistry proxy
  console.log("1. Checking IdentityRegistry proxy...");
  const currentIdentityImpl = await getImplementation(identityProxyAddress);
  const currentIdentityImplAddress = currentIdentityImpl ? `0x${currentIdentityImpl.slice(-40)}` : null;

  if (currentIdentityImplAddress?.toLowerCase() === identityImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to IdentityRegistryUpgradeable");
    console.log(`   Current implementation: ${identityImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading IdentityRegistry proxy...");
    const identityUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [identityImpl, "0x" as `0x${string}`]
    });
    const identityUpgradeTxHash = await ownerWallet.sendTransaction({
      to: identityProxyAddress,
      data: identityUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityUpgradeTxHash });
    console.log("   ✅ Upgraded to IdentityRegistryUpgradeable");
    console.log(`   Transaction: ${identityUpgradeTxHash}`);
    console.log("");
  }

  // Upgrade ReputationRegistry proxy
  console.log("2. Checking ReputationRegistry proxy...");
  const currentReputationImpl = await getImplementation(reputationProxyAddress);
  const currentReputationImplAddress = currentReputationImpl ? `0x${currentReputationImpl.slice(-40)}` : null;

  if (currentReputationImplAddress?.toLowerCase() === reputationImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to ReputationRegistryUpgradeable");
    console.log(`   Current implementation: ${reputationImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading ReputationRegistry proxy...");
    const reputationUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [reputationImpl, "0x" as `0x${string}`]
    });
    const reputationUpgradeTxHash = await ownerWallet.sendTransaction({
      to: reputationProxyAddress,
      data: reputationUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationUpgradeTxHash });
    console.log("   ✅ Upgraded to ReputationRegistryUpgradeable");
    console.log(`   Transaction: ${reputationUpgradeTxHash}`);
    console.log("");
  }

  // Upgrade ValidationRegistry proxy
  console.log("3. Checking ValidationRegistry proxy...");
  const currentValidationImpl = await getImplementation(validationProxyAddress);
  const currentValidationImplAddress = currentValidationImpl ? `0x${currentValidationImpl.slice(-40)}` : null;

  if (currentValidationImplAddress?.toLowerCase() === validationImpl.toLowerCase()) {
    console.log("   ⏭️  Already upgraded to ValidationRegistryUpgradeable");
    console.log(`   Current implementation: ${validationImpl}`);
    console.log("");
  } else {
    console.log("   Upgrading ValidationRegistry proxy...");
    const validationUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [validationImpl, "0x" as `0x${string}`]
    });
    const validationUpgradeTxHash = await ownerWallet.sendTransaction({
      to: validationProxyAddress,
      data: validationUpgradeData,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationUpgradeTxHash });
    console.log("   ✅ Upgraded to ValidationRegistryUpgradeable");
    console.log(`   Transaction: ${validationUpgradeTxHash}`);
    console.log("");
  }

  console.log("=".repeat(80));
  console.log("UPGRADES COMPLETE");
  console.log("=".repeat(80));
  console.log("");
  console.log("✅ All 3 proxies upgraded successfully!");
  console.log("");
  console.log("Next step: Verify deployment");
  console.log("  npm run verify:vanity -- --network <network>");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
