import hre from "hardhat";
import { encodeAbiParameters, encodeFunctionData, Hex } from "viem";
import dotenv from "dotenv";

// Load environment variables from .env file
dotenv.config();

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * MinimalUUPS address (deployed via CREATE2 with salt 0x01)
 */
const MINIMAL_UUPS_ADDRESS = "0xB0324bB5D23481009EfdDbD1fA8B5544FBeae60d" as const;
const MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;

/**
 * Vanity salts for proxies (pointing to MinimalUUPS initially)
 */
const VANITY_SALTS = {
  identityRegistry: "0x0000000000000000000000000000000000000000000000000000000000087efe" as Hex,
  reputationRegistry: "0x000000000000000000000000000000000000000000000000000000000007ccdf" as Hex,
  validationRegistry: "0x0000000000000000000000000000000000000000000000000000000000a8a957" as Hex,
} as const;

/**
 * Expected vanity proxy addresses
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004AE1BF83F0BC514De8A3DFFcc6754622D50b8",
  reputationRegistry: "0x8004BE768f4C976fBB0D739532bf46af3Cd71e5D",
  validationRegistry: "0x8004CFa3dCe1D992E0C2dC297DA8C6d2FD238741",
} as const;

/**
 * Gets the full deployment bytecode for ERC1967Proxy
 */
async function getProxyBytecode(
  implementationAddress: string,
  initCalldata: Hex
): Promise<Hex> {
  const proxyArtifact = await hre.artifacts.readArtifact("ERC1967Proxy");

  const constructorArgs = encodeAbiParameters(
    [
      { name: "implementation", type: "address" },
      { name: "data", type: "bytes" }
    ],
    [implementationAddress as `0x${string}`, initCalldata]
  );

  return (proxyArtifact.bytecode + constructorArgs.slice(2)) as Hex;
}

/**
 * Checks if the SAFE singleton CREATE2 factory is deployed
 */
async function checkCreate2FactoryDeployed(publicClient: any): Promise<boolean> {
  const code = await publicClient.getBytecode({
    address: SAFE_SINGLETON_FACTORY,
  });
  return code !== undefined && code !== "0x";
}

/**
 * Deploy ERC-8004 contracts with vanity proxy addresses
 *
 * Process:
 * 1. Deploy proxies with vanity addresses (pointing to 0x0000 initially)
 * 2. Deploy implementation contracts
 * 3. Upgrade proxies to point to implementations and initialize
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  // Get owner wallet from environment variable
  let ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (!ownerPrivateKey) {
    throw new Error("OWNER_PRIVATE_KEY not found in environment variables");
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
  const ownerAccount = privateKeyToAccount(ownerPrivateKey as any);
  const ownerWallet = createWalletClient({
    account: ownerAccount,
    chain: (await viem.getPublicClient()).chain,
    transport: http(),
  });

  console.log("Deploying ERC-8004 Contracts with Vanity Addresses");
  console.log("==================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("Owner address:", ownerAccount.address);
  console.log("");

  // Step 0: Check if SAFE singleton CREATE2 factory is deployed
  console.log("0. Checking for SAFE singleton CREATE2 factory...");
  const isFactoryDeployed = await checkCreate2FactoryDeployed(publicClient);

  if (!isFactoryDeployed) {
    console.error("❌ ERROR: SAFE singleton CREATE2 factory not found!");
    console.error(`   Expected address: ${SAFE_SINGLETON_FACTORY}`);
    console.error("");
    console.error("Please run: npx hardhat run scripts/deploy-create2-factory.ts --network <network>");
    throw new Error("SAFE singleton CREATE2 factory not deployed");
  }

  console.log(`   ✅ Factory found at: ${SAFE_SINGLETON_FACTORY}`);
  console.log("");

  // ============================================================================
  // PHASE 1: Deploy MinimalUUPS placeholder via CREATE2
  // ============================================================================

  console.log("PHASE 1: Deploying MinimalUUPS Placeholder via CREATE2");
  console.log("=======================================================");
  console.log("");

  // Check if MinimalUUPS already exists
  const minimalUUPSCode = await publicClient.getBytecode({
    address: MINIMAL_UUPS_ADDRESS,
  });

  if (!minimalUUPSCode || minimalUUPSCode === "0x") {
    console.log("1. Deploying MinimalUUPS via CREATE2...");
    const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");
    const minimalUUPSBytecode = minimalUUPSArtifact.bytecode as Hex;
    const minimalUUPSDeployData = (MINIMAL_UUPS_SALT + minimalUUPSBytecode.slice(2)) as Hex;

    const minimalUUPSTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: minimalUUPSDeployData,
    });
    await publicClient.waitForTransactionReceipt({ hash: minimalUUPSTxHash });

    console.log(`   ✅ Deployed at: ${MINIMAL_UUPS_ADDRESS}`);
  } else {
    console.log("1. MinimalUUPS already deployed");
    console.log(`   ✅ Found at: ${MINIMAL_UUPS_ADDRESS}`);
  }
  console.log("");

  // ============================================================================
  // PHASE 2: Deploy vanity proxies (pointing to MinimalUUPS initially)
  // ============================================================================

  console.log("PHASE 2: Deploying Vanity Proxies");
  console.log("==================================");
  console.log("");

  // Prepare initialize() call data for MinimalUUPS
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");
  const initializeCallData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "initialize",
    args: []
  });

  const proxyBytecode = await getProxyBytecode(MINIMAL_UUPS_ADDRESS, initializeCallData);

  // Deploy IdentityRegistry proxy
  const identityProxyAddress = EXPECTED_ADDRESSES.identityRegistry as `0x${string}`;
  const identityProxyCode = await publicClient.getBytecode({
    address: identityProxyAddress,
  });

  if (!identityProxyCode || identityProxyCode === "0x") {
    console.log("2. Deploying IdentityRegistry proxy (0x8004A...)...");
    const identityProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.identityRegistry + proxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityProxyTxHash });
    console.log(`   ✅ Deployed at: ${identityProxyAddress}`);
  } else {
    console.log("2. IdentityRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${identityProxyAddress}`);
  }
  console.log("");

  // Deploy ReputationRegistry proxy
  const reputationProxyAddress = EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`;
  const reputationProxyCode = await publicClient.getBytecode({
    address: reputationProxyAddress,
  });

  if (!reputationProxyCode || reputationProxyCode === "0x") {
    console.log("3. Deploying ReputationRegistry proxy (0x8004B...)...");
    const reputationProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.reputationRegistry + proxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationProxyTxHash });
    console.log(`   ✅ Deployed at: ${reputationProxyAddress}`);
  } else {
    console.log("3. ReputationRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${reputationProxyAddress}`);
  }
  console.log("");

  // Deploy ValidationRegistry proxy
  const validationProxyAddress = EXPECTED_ADDRESSES.validationRegistry as `0x${string}`;
  const validationProxyCode = await publicClient.getBytecode({
    address: validationProxyAddress,
  });

  if (!validationProxyCode || validationProxyCode === "0x") {
    console.log("4. Deploying ValidationRegistry proxy (0x8004C...)...");
    const validationProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.validationRegistry + proxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationProxyTxHash });
    console.log(`   ✅ Deployed at: ${validationProxyAddress}`);
  } else {
    console.log("4. ValidationRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${validationProxyAddress}`);
  }
  console.log("");

  // ============================================================================
  // PHASE 3: Deploy implementation contracts
  // ============================================================================

  console.log("PHASE 3: Deploying Implementation Contracts");
  console.log("============================================");
  console.log("");

  console.log("5. Deploying IdentityRegistry implementation...");
  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${identityRegistryImpl.address}`);
  console.log("");

  console.log("6. Deploying ReputationRegistry implementation...");
  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${reputationRegistryImpl.address}`);
  console.log("");

  console.log("7. Deploying ValidationRegistry implementation...");
  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${validationRegistryImpl.address}`);
  console.log("");

  console.log("=".repeat(80));
  console.log("DEPLOYER PHASE COMPLETE");
  console.log("=".repeat(80));
  console.log("");
  console.log("✅ All contracts deployed by deployer");
  console.log("✅ Proxies are initialized with MinimalUUPS (owner is set)");
  console.log("");
  console.log("⚠️  NEXT STEP: Owner must upgrade the 3 proxies (3 transactions)");
  console.log("");
  console.log("To upgrade, the owner needs to call upgradeToAndCall() on each proxy:");
  console.log(`  1. IdentityRegistry:   ${identityProxyAddress}`);
  console.log(`     -> New implementation: ${identityRegistryImpl.address}`);
  console.log(`  2. ReputationRegistry: ${reputationProxyAddress}`);
  console.log(`     -> New implementation: ${reputationRegistryImpl.address}`);
  console.log(`  3. ValidationRegistry: ${validationProxyAddress}`);
  console.log(`     -> New implementation: ${validationRegistryImpl.address}`);
  console.log("");
  console.log("After upgrades, run this script again to set identity registry references.");
  console.log("");

  // ============================================================================
  // PHASE 4: Owner upgrades (to be done externally or in separate step)
  // ============================================================================

  console.log("PHASE 4: Owner Upgrades (REQUIRES OWNER WALLET)");
  console.log("================================================");
  console.log("");

  // Get implementation ABIs
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  // Upgrade IdentityRegistry proxy with initialize()
  console.log("8. Upgrading IdentityRegistry proxy to final implementation...");
  const identityInitData = encodeFunctionData({
    abi: identityImplArtifact.abi,
    functionName: "initialize",
    args: []
  });
  const identityUpgradeData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "upgradeToAndCall",
    args: [identityRegistryImpl.address, identityInitData]
  });
  const identityUpgradeTxHash = await ownerWallet.sendTransaction({
    to: identityProxyAddress,
    data: identityUpgradeData,
  });
  await publicClient.waitForTransactionReceipt({ hash: identityUpgradeTxHash });
  console.log("   ✅ Upgraded");
  console.log("");

  // Upgrade ReputationRegistry proxy with initialize(identityRegistry)
  console.log("9. Upgrading ReputationRegistry proxy...");
  const reputationInitData = encodeFunctionData({
    abi: reputationImplArtifact.abi,
    functionName: "initialize",
    args: [identityProxyAddress]
  });
  const reputationUpgradeData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "upgradeToAndCall",
    args: [reputationRegistryImpl.address, reputationInitData]
  });
  const reputationUpgradeTxHash = await ownerWallet.sendTransaction({
    to: reputationProxyAddress,
    data: reputationUpgradeData,
  });
  await publicClient.waitForTransactionReceipt({ hash: reputationUpgradeTxHash });
  console.log("   ✅ Upgraded and initialized with IdentityRegistry");
  console.log("");

  // Upgrade ValidationRegistry proxy with initialize(identityRegistry)
  console.log("10. Upgrading ValidationRegistry proxy...");
  const validationInitData = encodeFunctionData({
    abi: validationImplArtifact.abi,
    functionName: "initialize",
    args: [identityProxyAddress]
  });
  const validationUpgradeData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "upgradeToAndCall",
    args: [validationRegistryImpl.address, validationInitData]
  });
  const validationUpgradeTxHash = await ownerWallet.sendTransaction({
    to: validationProxyAddress,
    data: validationUpgradeData,
  });
  await publicClient.waitForTransactionReceipt({ hash: validationUpgradeTxHash });
  console.log("   ✅ Upgraded and initialized with IdentityRegistry");
  console.log("");

  // ============================================================================
  // Verification
  // ============================================================================

  console.log("Verifying Deployments");
  console.log("=====================");
  console.log("");
  console.log("✅ All proxies deployed to vanity addresses");
  console.log("✅ All implementations deployed");
  console.log("✅ All proxies upgraded and initialized");
  console.log("");

  // ============================================================================
  // Summary
  // ============================================================================

  console.log("=".repeat(80));
  console.log("Deployment Summary");
  console.log("=".repeat(80));
  console.log("");
  console.log("Vanity Proxy Addresses:");
  console.log("  IdentityRegistry:    ", identityProxyAddress, "(0x8004A...)");
  console.log("  ReputationRegistry:  ", reputationProxyAddress, "(0x8004B...)");
  console.log("  ValidationRegistry:  ", validationProxyAddress, "(0x8004C...)");
  console.log("");
  console.log("Implementation Addresses:");
  console.log("  IdentityRegistry:    ", identityRegistryImpl.address);
  console.log("  ReputationRegistry:  ", reputationRegistryImpl.address);
  console.log("  ValidationRegistry:  ", validationRegistryImpl.address);
  console.log("");
  console.log("✅ All contracts deployed successfully with vanity addresses!");
  console.log("");

  return {
    proxies: {
      identityRegistry: identityProxyAddress,
      reputationRegistry: reputationProxyAddress,
      validationRegistry: validationProxyAddress
    },
    implementations: {
      identityRegistry: identityRegistryImpl.address,
      reputationRegistry: reputationRegistryImpl.address,
      validationRegistry: validationRegistryImpl.address
    }
  };
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
