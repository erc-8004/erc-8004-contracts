import hre from "hardhat";
import { encodeFunctionData, Hex, keccak256, getCreate2Address } from "viem";
import dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Salts for implementation contracts (must match deploy-vanity.ts)
 */
const IMPLEMENTATION_SALTS = {
  identityRegistry: "0x0000000000000000000000000000000000000000000000000000000000000005" as Hex,
  reputationRegistry: "0x0000000000000000000000000000000000000000000000000000000000000006" as Hex,
  validationRegistry: "0x0000000000000000000000000000000000000000000000000000000000000007" as Hex,
} as const;

/**
 * Expected vanity proxy addresses (deterministic across all networks)
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004A818BFB912233c491871b3d84c89A494BD9e",
  reputationRegistry: "0x8004B663056A597Dffe9eCcC1965A193B7388713",
  validationRegistry: "0x8004Cb1BF31DAf7788923b405b754f57acEB4272",
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

  // Calculate implementation addresses via CREATE2
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  const identityImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.identityRegistry,
    bytecodeHash: keccak256(identityImplArtifact.bytecode as Hex),
  });
  const reputationImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.reputationRegistry,
    bytecodeHash: keccak256(reputationImplArtifact.bytecode as Hex),
  });
  const validationImpl = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.validationRegistry,
    bytecodeHash: keccak256(validationImplArtifact.bytecode as Hex),
  });

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

  // Get MinimalUUPS ABI for upgradeToAndCall
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");

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
    // Encode initialize() call for the new implementation
    const identityInitData = encodeFunctionData({
      abi: identityImplArtifact.abi,
      functionName: "initialize",
      args: []
    });
    const identityUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [identityImpl, identityInitData]
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
    // Encode initialize(address) call for the new implementation
    const reputationInitData = encodeFunctionData({
      abi: reputationImplArtifact.abi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const reputationUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [reputationImpl, reputationInitData]
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
    // Encode initialize(address) call for the new implementation
    const validationInitData = encodeFunctionData({
      abi: validationImplArtifact.abi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const validationUpgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [validationImpl, validationInitData]
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
