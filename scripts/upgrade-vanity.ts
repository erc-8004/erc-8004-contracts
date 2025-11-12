import hre from "hardhat";
import { encodeFunctionData, Hex } from "viem";
import dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

/**
 * Expected vanity proxy addresses (deterministic across all networks)
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004AbdDA9b877187bF865eD1d8B5A41Da3c4997",
  reputationRegistry: "0x8004B312333aCb5764597c2BeEe256596B5C6876",
  validationRegistry: "0x8004C8AEF64521bC97AB50799d394CDb785885E3",
} as const;

/**
 * Implementation addresses (deployed via CREATE2, deterministic across all networks)
 */
const IMPLEMENTATION_ADDRESSES = {
  identityRegistry: "0x5B1e1fbACf33Cca26Eb8da79918EE8544eA1CF13",
  reputationRegistry: "0x11E6Aed2BC5a1370352010a40ba0Df533887DcA2",
  validationRegistry: "0x34A8244cfCF50433FEE0263EF54649dd85eAD2C4",
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

  // Upgrade IdentityRegistry proxy
  console.log("1. Upgrading IdentityRegistry proxy...");
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

  // Upgrade ReputationRegistry proxy
  console.log("2. Upgrading ReputationRegistry proxy...");
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

  // Upgrade ValidationRegistry proxy
  console.log("3. Upgrading ValidationRegistry proxy...");
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
