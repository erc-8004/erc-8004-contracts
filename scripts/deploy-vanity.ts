import hre from "hardhat";
import { encodeAbiParameters, encodeFunctionData, Hex, keccak256, getCreate2Address } from "viem";
import dotenv from "dotenv";
import {
  SAFE_SINGLETON_FACTORY,
  IMPLEMENTATION_SALTS,
  getAddresses,
  getVanitySalts,
  getMinimalUUPSContract,
  getMinimalUUPSSalt,
  getNetworkType,
} from "./addresses";

// Load environment variables from .env file
dotenv.config();

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

  // Get chainId and network-specific config
  const chainId = await publicClient.getChainId();
  const networkType = getNetworkType(chainId);
  const EXPECTED_ADDRESSES = getAddresses(chainId);
  const VANITY_SALTS = getVanitySalts(chainId);
  const MINIMAL_UUPS_CONTRACT = getMinimalUUPSContract(chainId);
  const MINIMAL_UUPS_SALT = getMinimalUUPSSalt(chainId);

  console.log("Deploying ERC-8004 Contracts with Vanity Addresses (Deployer Phase)");
  console.log("=====================================================================");
  console.log("Network type:", networkType);
  console.log("Chain ID:", chainId);
  console.log("MinimalUUPS contract:", MINIMAL_UUPS_CONTRACT);
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
  // PHASE 1: Deploy MinimalUUPS placeholder via CREATE2 (single instance)
  // ============================================================================

  console.log(`PHASE 1: Deploying ${MINIMAL_UUPS_CONTRACT} Placeholder via CREATE2`);
  console.log("=======================================================");
  console.log("");

  const minimalUUPSArtifact = await hre.artifacts.readArtifact(MINIMAL_UUPS_CONTRACT);
  const minimalUUPSBytecode = minimalUUPSArtifact.bytecode as Hex;

  // Calculate MinimalUUPS address
  const minimalUUPSAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: MINIMAL_UUPS_SALT,
    bytecodeHash: keccak256(minimalUUPSBytecode),
  });

  const minimalUUPSCode = await publicClient.getBytecode({ address: minimalUUPSAddress });

  if (!minimalUUPSCode || minimalUUPSCode === "0x") {
    console.log(`Deploying ${MINIMAL_UUPS_CONTRACT}...`);
    const deployData = (MINIMAL_UUPS_SALT + minimalUUPSBytecode.slice(2)) as Hex;

    const txHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: deployData,
    });
    await publicClient.waitForTransactionReceipt({ hash: txHash });
    console.log(`   ✅ Deployed at: ${minimalUUPSAddress}`);
  } else {
    console.log(`${MINIMAL_UUPS_CONTRACT} already deployed`);
    console.log(`   ✅ Found at: ${minimalUUPSAddress}`);
  }
  console.log("");

  // ============================================================================
  // PHASE 2: Deploy vanity proxies (pointing to MinimalUUPS initially)
  // ============================================================================

  console.log(`PHASE 2: Deploying Vanity Proxies (pointing to ${MINIMAL_UUPS_CONTRACT})`);
  console.log("==================================");
  console.log("");

  // Deploy IdentityRegistry proxy - initialize with zero address (doesn't need identityRegistry)
  const identityProxyAddress = EXPECTED_ADDRESSES.identityRegistry as `0x${string}`;
  const identityProxyCode = await publicClient.getBytecode({
    address: identityProxyAddress,
  });

  if (!identityProxyCode || identityProxyCode === "0x") {
    console.log("2. Deploying IdentityRegistry proxy (0x8004A...)...");
    const identityInitData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "initialize",
      args: ["0x0000000000000000000000000000000000000000" as `0x${string}`]
    });
    const identityProxyBytecode = await getProxyBytecode(minimalUUPSAddress, identityInitData);
    const identityProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.identityRegistry + identityProxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityProxyTxHash });
    console.log(`   ✅ Deployed at: ${identityProxyAddress}`);
  } else {
    console.log("2. IdentityRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${identityProxyAddress}`);
  }
  console.log("");

  // Deploy ReputationRegistry proxy - initialize with identityRegistry address
  const reputationProxyAddress = EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`;
  const reputationProxyCode = await publicClient.getBytecode({
    address: reputationProxyAddress,
  });

  if (!reputationProxyCode || reputationProxyCode === "0x") {
    console.log("3. Deploying ReputationRegistry proxy (0x8004B...)...");
    const reputationInitData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const reputationProxyBytecode = await getProxyBytecode(minimalUUPSAddress, reputationInitData);
    const reputationProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.reputationRegistry + reputationProxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationProxyTxHash });
    console.log(`   ✅ Deployed at: ${reputationProxyAddress}`);
  } else {
    console.log("3. ReputationRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${reputationProxyAddress}`);
  }
  console.log("");

  // Deploy ValidationRegistry proxy - initialize with identityRegistry address
  const validationProxyAddress = EXPECTED_ADDRESSES.validationRegistry as `0x${string}`;
  const validationProxyCode = await publicClient.getBytecode({
    address: validationProxyAddress,
  });

  if (!validationProxyCode || validationProxyCode === "0x") {
    console.log("4. Deploying ValidationRegistry proxy (0x8004C...)...");
    const validationInitData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "initialize",
      args: [identityProxyAddress]
    });
    const validationProxyBytecode = await getProxyBytecode(minimalUUPSAddress, validationInitData);
    const validationProxyTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: (VANITY_SALTS.validationRegistry + validationProxyBytecode.slice(2)) as Hex,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationProxyTxHash });
    console.log(`   ✅ Deployed at: ${validationProxyAddress}`);
  } else {
    console.log("4. ValidationRegistry proxy already deployed");
    console.log(`   ✅ Found at: ${validationProxyAddress}`);
  }
  console.log("");

  // ============================================================================
  // PHASE 3: Deploy implementation contracts via CREATE2
  // ============================================================================

  console.log("PHASE 3: Deploying Implementation Contracts via CREATE2");
  console.log("========================================================");
  console.log("");

  // Deploy IdentityRegistry implementation via CREATE2
  console.log("5. Deploying IdentityRegistry implementation via CREATE2...");
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const identityImplBytecode = identityImplArtifact.bytecode as Hex;
  const identityImplDeployData = (IMPLEMENTATION_SALTS.identityRegistry + identityImplBytecode.slice(2)) as Hex;

  // Calculate the CREATE2 address
  const identityRegistryImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.identityRegistry,
    bytecodeHash: keccak256(identityImplBytecode),
  });

  // Check if already deployed
  const identityImplCode = await publicClient.getBytecode({ address: identityRegistryImplAddress });

  if (!identityImplCode || identityImplCode === "0x") {
    const identityImplTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: identityImplDeployData,
    });
    await publicClient.waitForTransactionReceipt({ hash: identityImplTxHash });
    console.log(`   ✅ Deployed at: ${identityRegistryImplAddress}`);
  } else {
    console.log(`   ✅ Already deployed at: ${identityRegistryImplAddress}`);
  }
  console.log("");

  // Deploy ReputationRegistry implementation via CREATE2
  console.log("6. Deploying ReputationRegistry implementation via CREATE2...");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const reputationImplBytecode = reputationImplArtifact.bytecode as Hex;
  const reputationImplDeployData = (IMPLEMENTATION_SALTS.reputationRegistry + reputationImplBytecode.slice(2)) as Hex;

  // Calculate the CREATE2 address
  const reputationRegistryImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.reputationRegistry,
    bytecodeHash: keccak256(reputationImplBytecode),
  });

  // Check if already deployed
  const reputationImplCode = await publicClient.getBytecode({ address: reputationRegistryImplAddress });

  if (!reputationImplCode || reputationImplCode === "0x") {
    const reputationImplTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: reputationImplDeployData,
    });
    await publicClient.waitForTransactionReceipt({ hash: reputationImplTxHash });
    console.log(`   ✅ Deployed at: ${reputationRegistryImplAddress}`);
  } else {
    console.log(`   ✅ Already deployed at: ${reputationRegistryImplAddress}`);
  }
  console.log("");

  // Deploy ValidationRegistry implementation via CREATE2
  console.log("7. Deploying ValidationRegistry implementation via CREATE2...");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");
  const validationImplBytecode = validationImplArtifact.bytecode as Hex;
  const validationImplDeployData = (IMPLEMENTATION_SALTS.validationRegistry + validationImplBytecode.slice(2)) as Hex;

  // Calculate the CREATE2 address
  const validationRegistryImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.validationRegistry,
    bytecodeHash: keccak256(validationImplBytecode),
  });

  // Check if already deployed
  const validationImplCode = await publicClient.getBytecode({ address: validationRegistryImplAddress });

  if (!validationImplCode || validationImplCode === "0x") {
    const validationImplTxHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: validationImplDeployData,
    });
    await publicClient.waitForTransactionReceipt({ hash: validationImplTxHash });
    console.log(`   ✅ Deployed at: ${validationRegistryImplAddress}`);
  } else {
    console.log(`   ✅ Already deployed at: ${validationRegistryImplAddress}`);
  }
  console.log("");

  console.log("=".repeat(80));
  console.log("DEPLOYMENT COMPLETE");
  console.log("=".repeat(80));
  console.log("");
  console.log("✅ All contracts deployed by deployer");
  console.log(`✅ Proxies are initialized with ${MINIMAL_UUPS_CONTRACT} (owner is set)`);
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
  console.log("  IdentityRegistry:    ", identityRegistryImplAddress);
  console.log("  ReputationRegistry:  ", reputationRegistryImplAddress);
  console.log("  ValidationRegistry:  ", validationRegistryImplAddress);
  console.log("");
  console.log("=".repeat(80));
  console.log("⚠️  NEXT STEPS");
  console.log("=".repeat(80));
  console.log("");
  console.log("1. Owner can generate 3 pre-signed upgrade transactions:");
  console.log("   npx hardhat run scripts/generate-triple-presigned-upgrade.ts --network <network>");
  console.log("");
  console.log("2. Broadcast all 3 pre-signed transactions:");
  console.log("   npx hardhat run scripts/broadcast-triple-presigned-upgrade.ts --network <network>");
  console.log("");
  console.log("3. Or upgrade manually (requires owner private key):");
  console.log("   npm run upgrade:vanity -- --network <network>");
  console.log("");

  return {
    proxies: {
      identityRegistry: identityProxyAddress,
      reputationRegistry: reputationProxyAddress,
      validationRegistry: validationProxyAddress
    },
    implementations: {
      identityRegistry: identityRegistryImplAddress,
      reputationRegistry: reputationRegistryImplAddress,
      validationRegistry: validationRegistryImplAddress
    }
  };
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
