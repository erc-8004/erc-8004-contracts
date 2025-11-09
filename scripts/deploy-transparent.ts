import hre from "hardhat";
import { encodeFunctionData } from "viem";

/**
 * Deploy ERC-8004 contracts using TransparentUpgradeableProxy
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying ERC-8004 Contracts with TransparentUpgradeableProxy");
  console.log("=============================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // ============================================================================
  // PHASE 1: Deploy implementation contracts
  // ============================================================================

  console.log("PHASE 1: Deploying Implementation Contracts");
  console.log("============================================");
  console.log("");

  console.log("1. Deploying IdentityRegistry implementation...");
  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${identityRegistryImpl.address}`);
  console.log("");

  console.log("2. Deploying ReputationRegistry implementation...");
  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${reputationRegistryImpl.address}`);
  console.log("");

  console.log("3. Deploying ValidationRegistry implementation...");
  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable");
  console.log(`   ✅ Deployed at: ${validationRegistryImpl.address}`);
  console.log("");

  // ============================================================================
  // PHASE 2: Deploy TransparentUpgradeableProxy for each contract
  // ============================================================================

  console.log("PHASE 2: Deploying Proxies");
  console.log("==========================");
  console.log("");

  // Get ABIs for encoding initialize calls
  const identityArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  // Deploy IdentityRegistry proxy
  console.log("4. Deploying IdentityRegistry proxy...");
  const identityInitData = encodeFunctionData({
    abi: identityArtifact.abi,
    functionName: "initialize",
    args: []
  });

  const identityProxy = await viem.deployContract("TransparentUpgradeableProxy", [
    identityRegistryImpl.address,
    deployer.account.address,
    identityInitData
  ]);
  console.log(`   ✅ Deployed at: ${identityProxy.address}`);
  console.log("");

  // Deploy ReputationRegistry proxy
  console.log("5. Deploying ReputationRegistry proxy...");
  const reputationInitData = encodeFunctionData({
    abi: reputationArtifact.abi,
    functionName: "initialize",
    args: [identityProxy.address]
  });

  const reputationProxy = await viem.deployContract("TransparentUpgradeableProxy", [
    reputationRegistryImpl.address,
    deployer.account.address,
    reputationInitData
  ]);
  console.log(`   ✅ Deployed at: ${reputationProxy.address}`);
  console.log("");

  // Deploy ValidationRegistry proxy
  console.log("6. Deploying ValidationRegistry proxy...");
  const validationInitData = encodeFunctionData({
    abi: validationArtifact.abi,
    functionName: "initialize",
    args: [identityProxy.address]
  });

  const validationProxy = await viem.deployContract("TransparentUpgradeableProxy", [
    validationRegistryImpl.address,
    deployer.account.address,
    validationInitData
  ]);
  console.log(`   ✅ Deployed at: ${validationProxy.address}`);
  console.log("");

  // ============================================================================
  // Verification
  // ============================================================================

  console.log("Verifying Deployments");
  console.log("=====================");
  console.log("");

  // Get contract interfaces for verification
  const identityRegistry = await viem.getContractAt(
    "IdentityRegistryUpgradeable",
    identityProxy.address
  );
  const reputationRegistry = await viem.getContractAt(
    "ReputationRegistryUpgradeable",
    reputationProxy.address
  );
  const validationRegistry = await viem.getContractAt(
    "ValidationRegistryUpgradeable",
    validationProxy.address
  );

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
  console.log("");

  // ============================================================================
  // Summary
  // ============================================================================

  console.log("=".repeat(80));
  console.log("Deployment Summary");
  console.log("=".repeat(80));
  console.log("");
  console.log("Proxy Addresses:");
  console.log("  IdentityRegistry:    ", identityProxy.address);
  console.log("  ReputationRegistry:  ", reputationProxy.address);
  console.log("  ValidationRegistry:  ", validationProxy.address);
  console.log("");
  console.log("Implementation Addresses:");
  console.log("  IdentityRegistry:    ", identityRegistryImpl.address);
  console.log("  ReputationRegistry:  ", reputationRegistryImpl.address);
  console.log("  ValidationRegistry:  ", validationRegistryImpl.address);
  console.log("");
  console.log("✅ All contracts deployed successfully!");
  console.log("");

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
