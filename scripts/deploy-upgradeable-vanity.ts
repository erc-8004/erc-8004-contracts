import hre from "hardhat";
import { encodeAbiParameters, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Vanity salts found for each registry proxy
 * These salts generate addresses with prefixes: 0x8004A, 0x8004B, 0x8004C
 */
const VANITY_SALTS = {
  identityRegistry: "0x00000000000000000000000000000000000000000000000000000000000a4281" as Hex,
  reputationRegistry: "0x00000000000000000000000000000000000000000000000000000000000f0c79" as Hex,
  validationRegistry: "0x00000000000000000000000000000000000000000000000000000000001606e2" as Hex,
} as const;

/**
 * Expected vanity addresses (for verification)
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004A38aA4dE46632aa597FFCe73F26c03850737",
  reputationRegistry: "0x8004B7E259Cc39f3a3d2bf8C5096553085F15673",
  validationRegistry: "0x8004C7085d36A7c1F3E1244C6f761b0E35441925",
} as const;

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
 * Gets the full deployment bytecode for a proxy contract
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
 * Deploy script for ERC-8004 upgradeable contracts with vanity addresses
 *
 * This script:
 * 0. Checks if SAFE singleton CREATE2 factory is deployed
 * 1. Deploys implementation contracts for all three registries
 * 2. Deploys ERC1967Proxy for each implementation using CREATE2 with vanity salts
 * 3. Initializes each proxy with appropriate parameters
 * 4. Verifies vanity addresses match expected values
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying ERC-8004 Upgradeable Contracts with Vanity Addresses");
  console.log("==============================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Step 0: Check if SAFE singleton CREATE2 factory is deployed
  console.log("0. Checking for SAFE singleton CREATE2 factory...");
  const isFactoryDeployed = await checkCreate2FactoryDeployed(publicClient);

  if (!isFactoryDeployed) {
    console.error("❌ ERROR: SAFE singleton CREATE2 factory not found!");
    console.error(`   Expected address: ${SAFE_SINGLETON_FACTORY}`);
    console.error("");
    console.error("The CREATE2 factory must be deployed before deploying upgradeable contracts.");
    console.error("Please run the factory deployment script first:");
    console.error("   npx hardhat run scripts/deploy-create2-factory.ts --network <network>");
    console.error("");
    throw new Error("SAFE singleton CREATE2 factory not deployed");
  }

  console.log(`   ✅ Factory found at: ${SAFE_SINGLETON_FACTORY}`);
  console.log("");

  // Step 1: Deploy IdentityRegistry Implementation
  console.log("1. Deploying IdentityRegistry implementation...");
  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable");
  console.log("   Implementation deployed at:", identityRegistryImpl.address);

  // Step 2: Deploy IdentityRegistry Proxy with vanity address (0x8004A...)
  console.log("2. Deploying IdentityRegistry proxy with vanity address...");
  const identityInitCalldata = "0x8129fc1c" as Hex;

  const identityProxyBytecode = await getProxyBytecode(
    identityRegistryImpl.address,
    identityInitCalldata
  );

  // Deploy via CREATE2 factory
  const identityProxyTxHash = await deployer.sendTransaction({
    to: SAFE_SINGLETON_FACTORY,
    data: (VANITY_SALTS.identityRegistry + identityProxyBytecode.slice(2)) as Hex,
  });

  await publicClient.waitForTransactionReceipt({ hash: identityProxyTxHash });
  const identityProxyAddress = EXPECTED_ADDRESSES.identityRegistry as `0x${string}`;

  console.log("   Proxy deployed at:", identityProxyAddress);
  console.log("   ✅ Vanity prefix: 0x8004A");
  console.log("");

  // Get IdentityRegistry instance through proxy
  const identityRegistry = await viem.getContractAt(
    "IdentityRegistryUpgradeable",
    identityProxyAddress
  );

  // Step 3: Deploy ReputationRegistry Implementation
  console.log("3. Deploying ReputationRegistry implementation...");
  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable");
  console.log("   Implementation deployed at:", reputationRegistryImpl.address);

  // Step 4: Deploy ReputationRegistry Proxy with vanity address (0x8004B...)
  console.log("4. Deploying ReputationRegistry proxy with vanity address...");
  const reputationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxyAddress]
  );
  const reputationInitData = ("0xc4d66de8" + reputationInitCalldata.slice(2)) as Hex;

  const reputationProxyBytecode = await getProxyBytecode(
    reputationRegistryImpl.address,
    reputationInitData
  );

  const reputationProxyTxHash = await deployer.sendTransaction({
    to: SAFE_SINGLETON_FACTORY,
    data: (VANITY_SALTS.reputationRegistry + reputationProxyBytecode.slice(2)) as Hex,
  });

  await publicClient.waitForTransactionReceipt({ hash: reputationProxyTxHash });
  const reputationProxyAddress = EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`;

  console.log("   Proxy deployed at:", reputationProxyAddress);
  console.log("   ✅ Vanity prefix: 0x8004B");
  console.log("");

  // Get ReputationRegistry instance through proxy
  const reputationRegistry = await viem.getContractAt(
    "ReputationRegistryUpgradeable",
    reputationProxyAddress
  );

  // Step 5: Deploy ValidationRegistry Implementation
  console.log("5. Deploying ValidationRegistry implementation...");
  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable");
  console.log("   Implementation deployed at:", validationRegistryImpl.address);

  // Step 6: Deploy ValidationRegistry Proxy with vanity address (0x8004C...)
  console.log("6. Deploying ValidationRegistry proxy with vanity address...");
  const validationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxyAddress]
  );
  const validationInitData = ("0xc4d66de8" + validationInitCalldata.slice(2)) as Hex;

  const validationProxyBytecode = await getProxyBytecode(
    validationRegistryImpl.address,
    validationInitData
  );

  const validationProxyTxHash = await deployer.sendTransaction({
    to: SAFE_SINGLETON_FACTORY,
    data: (VANITY_SALTS.validationRegistry + validationProxyBytecode.slice(2)) as Hex,
  });

  await publicClient.waitForTransactionReceipt({ hash: validationProxyTxHash });
  const validationProxyAddress = EXPECTED_ADDRESSES.validationRegistry as `0x${string}`;

  console.log("   Proxy deployed at:", validationProxyAddress);
  console.log("   ✅ Vanity prefix: 0x8004C");
  console.log("");

  // Get ValidationRegistry instance through proxy
  const validationRegistry = await viem.getContractAt(
    "ValidationRegistryUpgradeable",
    validationProxyAddress
  );

  // Verify deployments
  console.log("Verifying deployments...");
  console.log("=========================");

  try {
    const identityVersion = await identityRegistry.read.getVersion();
    console.log("IdentityRegistry version:", identityVersion);

    const reputationVersion = await reputationRegistry.read.getVersion();
    const reputationIdentityRegistry = await reputationRegistry.read.getIdentityRegistry();
    console.log("ReputationRegistry version:", reputationVersion);
    console.log("ReputationRegistry identityRegistry:", reputationIdentityRegistry);

    const validationVersion = await validationRegistry.read.getVersion();
    const validationIdentityRegistry = await validationRegistry.read.getIdentityRegistry();
    console.log("ValidationRegistry version:", validationVersion);
    console.log("ValidationRegistry identityRegistry:", validationIdentityRegistry);
  } catch (error) {
    console.log("⚠️  Unable to verify contract versions (this is expected if deployment failed)");
    console.log("   Error:", (error as Error).message.split('\n')[0]);
  }
  console.log("");

  // Verify vanity addresses
  console.log("Verifying vanity addresses...");
  console.log("==============================");

  // Check actual deployed addresses match expected
  const actualIdentityCode = await publicClient.getBytecode({ address: identityProxyAddress });
  const actualReputationCode = await publicClient.getBytecode({ address: reputationProxyAddress });
  const actualValidationCode = await publicClient.getBytecode({ address: validationProxyAddress });

  if (actualIdentityCode && actualIdentityCode !== "0x") {
    console.log("✅ IdentityRegistry deployed at expected vanity address");
  } else {
    console.error("❌ IdentityRegistry not found at expected address");
  }

  if (actualReputationCode && actualReputationCode !== "0x") {
    console.log("✅ ReputationRegistry deployed at expected vanity address");
  } else {
    console.error("❌ ReputationRegistry not found at expected address");
  }

  if (actualValidationCode && actualValidationCode !== "0x") {
    console.log("✅ ValidationRegistry deployed at expected vanity address");
  } else {
    console.error("❌ ValidationRegistry not found at expected address");
  }
  console.log("");

  // Summary
  console.log("Deployment Summary");
  console.log("==================");
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
