import hre from "hardhat";

/**
 * Sleep for a specified number of milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Deploy script for ERC-8004 upgradeable contracts on Polygon (no vanity addresses)
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying ERC-8004 Upgradeable Contracts (Polygon)");
  console.log("==================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Step 1: Deploy IdentityRegistry Implementation
  console.log("1. Deploying IdentityRegistry implementation...");
  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable", [], {
    gas: 10000000n,
  });
  console.log("   Implementation deployed at:", identityRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 2: Deploy IdentityRegistry Proxy
  console.log("2. Deploying IdentityRegistry proxy...");
  const identityInitCalldata = "0x8129fc1c" as `0x${string}`;
  const identityProxy = await viem.deployContract("ERC1967Proxy", [
    identityRegistryImpl.address,
    identityInitCalldata
  ], {
    gas: 5000000n,
  });
  console.log("   Proxy deployed at:", identityProxy.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  const identityRegistry = await viem.getContractAt(
    "IdentityRegistryUpgradeable",
    identityProxy.address
  );

  // Step 3: Deploy ReputationRegistry Implementation
  console.log("3. Deploying ReputationRegistry implementation...");
  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable");
  console.log("   Implementation deployed at:", reputationRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 4: Deploy ReputationRegistry Proxy
  console.log("4. Deploying ReputationRegistry proxy...");
  const reputationProxy = await viem.deployContract("ERC1967Proxy", [
    reputationRegistryImpl.address,
    "0x" as `0x${string}`
  ]);
  console.log("   Proxy deployed at:", reputationProxy.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const reputationRegistry = await viem.getContractAt(
    "ReputationRegistryUpgradeable",
    reputationProxy.address
  );

  // Initialize ReputationRegistry
  console.log("   Initializing ReputationRegistry...");
  const repInitTx = await reputationRegistry.write.initialize([identityProxy.address]);
  await publicClient.waitForTransactionReceipt({ hash: repInitTx });
  console.log("   Initialized");
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  // Step 5: Deploy ValidationRegistry Implementation
  console.log("5. Deploying ValidationRegistry implementation...");
  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable");
  console.log("   Implementation deployed at:", validationRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 6: Deploy ValidationRegistry Proxy
  console.log("6. Deploying ValidationRegistry proxy...");
  const validationProxy = await viem.deployContract("ERC1967Proxy", [
    validationRegistryImpl.address,
    "0x" as `0x${string}`
  ]);
  console.log("   Proxy deployed at:", validationProxy.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const validationRegistry = await viem.getContractAt(
    "ValidationRegistryUpgradeable",
    validationProxy.address
  );

  // Initialize ValidationRegistry
  console.log("   Initializing ValidationRegistry...");
  const valInitTx = await validationRegistry.write.initialize([identityProxy.address]);
  await publicClient.waitForTransactionReceipt({ hash: valInitTx });
  console.log("   Initialized");
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  // Verify deployments
  console.log("Verifying deployments...");
  console.log("=========================");

  const identityVersion = await identityRegistry.read.getVersion();
  console.log("IdentityRegistry version:", identityVersion);
  console.log("Waiting 3 seconds...");
  await sleep(3000);

  const reputationVersion = await reputationRegistry.read.getVersion();
  console.log("ReputationRegistry version:", reputationVersion);
  console.log("Waiting 3 seconds...");
  await sleep(3000);
  const reputationIdentityRegistry = await reputationRegistry.read.getIdentityRegistry();
  console.log("ReputationRegistry identityRegistry:", reputationIdentityRegistry);
  console.log("Waiting 3 seconds...");
  await sleep(3000);

  const validationVersion = await validationRegistry.read.getVersion();
  console.log("ValidationRegistry version:", validationVersion);
  console.log("Waiting 3 seconds...");
  await sleep(3000);
  const validationIdentityRegistry = await validationRegistry.read.getIdentityRegistry();
  console.log("ValidationRegistry identityRegistry:", validationIdentityRegistry);
  console.log("");

  // Summary
  console.log("Deployment Summary");
  console.log("==================");
  console.log("IdentityRegistry Proxy:", identityProxy.address);
  console.log("ReputationRegistry Proxy:", reputationProxy.address);
  console.log("ValidationRegistry Proxy:", validationProxy.address);
  console.log("");
  console.log("Implementation Addresses:");
  console.log("IdentityRegistry Implementation:", identityRegistryImpl.address);
  console.log("ReputationRegistry Implementation:", reputationRegistryImpl.address);
  console.log("ValidationRegistry Implementation:", validationRegistryImpl.address);
  console.log("");
  console.log("✅ All contracts deployed successfully!");

  return {
    proxies: {
      identityRegistry: identityProxy.address,
      reputationRegistry: reputationProxy.address,
      validationRegistry: validationProxy.address
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
