import hre from "hardhat";
import { getCreate2Address, keccak256, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Deterministic salts for implementation contracts
 * Using simple, memorable salts since implementations don't need vanity addresses
 */
const IMPL_SALTS = {
  identityRegistry: "0x0000000000000000000000000000000000000000000000000000000000008004" as Hex,
  reputationRegistry: "0x0000000000000000000000000000000000000000000000000000000000008004" as Hex,
  validationRegistry: "0x0000000000000000000000000000000000000000000000000000000000008004" as Hex,
} as const;

/**
 * Computes CREATE2 address for a contract
 */
function computeCreate2Address(
  factoryAddress: string,
  bytecode: Hex,
  salt: Hex
): string {
  return getCreate2Address({
    from: factoryAddress,
    salt,
    bytecode,
  });
}

/**
 * Deploy implementation contracts using CREATE2 for deterministic addresses
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying ERC-8004 Implementation Contracts with CREATE2");
  console.log("========================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Get contract artifacts
  const identityArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  const identityBytecode = identityArtifact.bytecode as Hex;
  const reputationBytecode = reputationArtifact.bytecode as Hex;
  const validationBytecode = validationArtifact.bytecode as Hex;

  // Compute expected addresses
  const identityImplAddress = computeCreate2Address(
    SAFE_SINGLETON_FACTORY,
    identityBytecode,
    IMPL_SALTS.identityRegistry
  );

  const reputationImplAddress = computeCreate2Address(
    SAFE_SINGLETON_FACTORY,
    reputationBytecode,
    IMPL_SALTS.reputationRegistry
  );

  const validationImplAddress = computeCreate2Address(
    SAFE_SINGLETON_FACTORY,
    validationBytecode,
    IMPL_SALTS.validationRegistry
  );

  console.log("Expected implementation addresses:");
  console.log("  IdentityRegistry:   ", identityImplAddress);
  console.log("  ReputationRegistry: ", reputationImplAddress);
  console.log("  ValidationRegistry: ", validationImplAddress);
  console.log("");

  // Deploy IdentityRegistry Implementation
  console.log("1. Deploying IdentityRegistry implementation via CREATE2...");
  const existingIdentityCode = await publicClient.getBytecode({
    address: identityImplAddress as `0x${string}`,
  });

  if (existingIdentityCode && existingIdentityCode !== "0x") {
    console.log("   ✅ Already deployed at:", identityImplAddress);
  } else {
    const identityTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (IMPL_SALTS.identityRegistry + identityBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityTxHash });
    console.log("   ✅ Deployed at:", identityImplAddress);
  }

  // Deploy ReputationRegistry Implementation
  console.log("2. Deploying ReputationRegistry implementation via CREATE2...");
  const existingReputationCode = await publicClient.getBytecode({
    address: reputationImplAddress as `0x${string}`,
  });

  if (existingReputationCode && existingReputationCode !== "0x") {
    console.log("   ✅ Already deployed at:", reputationImplAddress);
  } else {
    const reputationTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (IMPL_SALTS.reputationRegistry + reputationBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationTxHash });
    console.log("   ✅ Deployed at:", reputationImplAddress);
  }

  // Deploy ValidationRegistry Implementation
  console.log("3. Deploying ValidationRegistry implementation via CREATE2...");
  const existingValidationCode = await publicClient.getBytecode({
    address: validationImplAddress as `0x${string}`,
  });

  if (existingValidationCode && existingValidationCode !== "0x") {
    console.log("   ✅ Already deployed at:", validationImplAddress);
  } else {
    const validationTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (IMPL_SALTS.validationRegistry + validationBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationTxHash });
    console.log("   ✅ Deployed at:", validationImplAddress);
  }

  console.log("");
  console.log("✅ All implementation contracts deployed!");
  console.log("");
  console.log("Implementation Addresses:");
  console.log("========================");
  console.log("IdentityRegistry:   ", identityImplAddress);
  console.log("ReputationRegistry: ", reputationImplAddress);
  console.log("ValidationRegistry: ", validationImplAddress);
  console.log("");

  return {
    identityRegistry: identityImplAddress,
    reputationRegistry: reputationImplAddress,
    validationRegistry: validationImplAddress,
  };
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
