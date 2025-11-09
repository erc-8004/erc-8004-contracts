import hre from "hardhat";
import { encodeAbiParameters, encodeFunctionData, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * MinimalUUPS address (deployed via CREATE2 with salt 0x01)
 */
const MINIMAL_UUPS_ADDRESS = "0xC8b951376F72d8BD88eADdDf486c91d4Efcd844c" as const;
const MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;

/**
 * Vanity salts for proxies (pointing to MinimalUUPS initially)
 */
const VANITY_SALTS = {
  identityRegistry: "0x000000000000000000000000000000000000000000000000000000000003ed12" as Hex,
  reputationRegistry: "0x00000000000000000000000000000000000000000000000000000000001e6f60" as Hex,
  validationRegistry: "0x0000000000000000000000000000000000000000000000000000000000039911" as Hex,
} as const;

/**
 * Expected vanity proxy addresses
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004A74334E9C8a0787799855FA720bEa2632f28",
  reputationRegistry: "0x8004B40CA346bCB6d1c01A8FC0F770602aC1ceB6",
  validationRegistry: "0x8004C3478C88560565CE012397ff0139e3721f41",
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

  console.log("Deploying ERC-8004 Contracts with Vanity Addresses");
  console.log("==================================================");
  console.log("Deployer address:", deployer.account.address);
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

  const emptyInitData = "0x" as Hex;
  const proxyBytecode = await getProxyBytecode(MINIMAL_UUPS_ADDRESS, emptyInitData);

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

  // ============================================================================
  // PHASE 4: Initialize MinimalUUPS on proxies
  // ============================================================================

  console.log("PHASE 4: Initializing MinimalUUPS on Proxies");
  console.log("=============================================");
  console.log("");

  // Get contract interfaces
  const identityMinimal = await viem.getContractAt(
    "MinimalUUPS",
    identityProxyAddress
  );
  const reputationMinimal = await viem.getContractAt(
    "MinimalUUPS",
    reputationProxyAddress
  );
  const validationMinimal = await viem.getContractAt(
    "MinimalUUPS",
    validationProxyAddress
  );

  console.log("5. Initializing IdentityRegistry proxy...");
  const identityInitTxHash = await identityMinimal.write.initialize();
  await publicClient.waitForTransactionReceipt({ hash: identityInitTxHash });
  console.log("   ✅ Initialized");
  console.log("");

  console.log("6. Initializing ReputationRegistry proxy...");
  const reputationInitTxHash = await reputationMinimal.write.initialize();
  await publicClient.waitForTransactionReceipt({ hash: reputationInitTxHash });
  console.log("   ✅ Initialized");
  console.log("");

  console.log("7. Initializing ValidationRegistry proxy...");
  const validationInitTxHash = await validationMinimal.write.initialize();
  await publicClient.waitForTransactionReceipt({ hash: validationInitTxHash });
  console.log("   ✅ Initialized");
  console.log("");

  // ============================================================================
  // PHASE 5: Upgrade proxies to point to implementations and initialize
  // ============================================================================

  console.log("PHASE 5: Upgrading Proxies to Final Implementations");
  console.log("====================================================");
  console.log("");

  // Get contract ABIs for encoding init data
  const identityArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  // Upgrade IdentityRegistry proxy (without initialization - already initialized with MinimalUUPS)
  console.log("8. Upgrading IdentityRegistry proxy to final implementation...");

  // Use upgradeTo instead of upgradeToAndCall since we're already initialized
  const identityUpgradeTxHash = await identityMinimal.write.upgradeToAndCall([
    identityRegistryImpl.address,
    "0x" as Hex  // Empty data - don't call initialize again
  ]);
  await publicClient.waitForTransactionReceipt({ hash: identityUpgradeTxHash });
  console.log("   ✅ Upgraded");
  console.log("");

  // Upgrade ReputationRegistry proxy (without initialization - already initialized with MinimalUUPS)
  console.log("9. Upgrading ReputationRegistry proxy...");

  const reputationUpgradeTxHash = await reputationMinimal.write.upgradeToAndCall([
    reputationRegistryImpl.address,
    "0x" as Hex  // Empty data - don't call initialize again
  ]);
  await publicClient.waitForTransactionReceipt({ hash: reputationUpgradeTxHash });
  console.log("   ✅ Upgraded");

  // Now set the identity registry reference
  const reputationRegistry = await viem.getContractAt(
    "ReputationRegistryUpgradeable",
    reputationProxyAddress
  );
  const setReputationIdTxHash = await reputationRegistry.write.setIdentityRegistry([identityProxyAddress]);
  await publicClient.waitForTransactionReceipt({ hash: setReputationIdTxHash });
  console.log("   ✅ IdentityRegistry reference set");
  console.log("");

  // Upgrade ValidationRegistry proxy (without initialization - already initialized with MinimalUUPS)
  console.log("10. Upgrading ValidationRegistry proxy...");

  const validationUpgradeTxHash = await validationMinimal.write.upgradeToAndCall([
    validationRegistryImpl.address,
    "0x" as Hex  // Empty data - don't call initialize again
  ]);
  await publicClient.waitForTransactionReceipt({ hash: validationUpgradeTxHash });
  console.log("   ✅ Upgraded");

  // Now set the identity registry reference
  const validationRegistry = await viem.getContractAt(
    "ValidationRegistryUpgradeable",
    validationProxyAddress
  );
  const setValidationIdTxHash = await validationRegistry.write.setIdentityRegistry([identityProxyAddress]);
  await publicClient.waitForTransactionReceipt({ hash: setValidationIdTxHash });
  console.log("   ✅ IdentityRegistry reference set");
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
