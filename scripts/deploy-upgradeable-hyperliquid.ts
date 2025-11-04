import hre from "hardhat";
import { getCreate2Address, keccak256, encodeAbiParameters, toHex } from "viem";

/**
 * Sleep for a specified number of milliseconds
 */
function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Find a salt that produces a CREATE2 address with the desired prefix
 */
function findVanitySalt(
  deployer: `0x${string}`,
  initCodeHash: `0x${string}`,
  desiredPrefix: string,
  maxIterations: number = 100000000
): { salt: `0x${string}`; address: `0x${string}` } | null {
  const prefix = desiredPrefix.toLowerCase();

  for (let i = 0; i < maxIterations; i++) {
    const salt = keccak256(toHex(i));
    const address = getCreate2Address({
      from: deployer,
      salt,
      bytecodeHash: initCodeHash,
    });

    if (address.toLowerCase().startsWith('0x' + prefix)) {
      return { salt, address };
    }

    // Log progress every 100k iterations
    if (i % 100000 === 0 && i > 0) {
      console.log(`   Checked ${i.toLocaleString()} salts...`);
    }
  }

  return null;
}

/**
 * Deploy script for ERC-8004 upgradeable contracts on Hyperliquid EVM Testnet using UUPS proxy pattern with CREATE2 vanity addresses
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying ERC-8004 Upgradeable Contracts (Hyperliquid Testnet)");
  console.log("==============================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Step 0: Deploy CREATE2 Factory
  console.log("0. Deploying CREATE2 Factory...");
  const factory = await viem.deployContract("Create2Factory", []);
  console.log("   Factory deployed at:", factory.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  // Step 1: Deploy IdentityRegistry Implementation
  console.log("1. Deploying IdentityRegistry implementation...");
  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable", []);
  console.log("   Implementation deployed at:", identityRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 2: Deploy IdentityRegistry Proxy with vanity address 0x8004a
  console.log("2. Deploying IdentityRegistry proxy with vanity address...");
  const identityInitCalldata = "0x8129fc1c" as `0x${string}`;

  const proxyArtifact = await hre.artifacts.readArtifact("ERC1967Proxy");
  const proxyBytecode = proxyArtifact.bytecode as `0x${string}`;

  const identityConstructorArgs = encodeAbiParameters(
    [{ type: "address" }, { type: "bytes" }],
    [identityRegistryImpl.address, identityInitCalldata]
  );

  const identityInitCode = (proxyBytecode + identityConstructorArgs.slice(2)) as `0x${string}`;
  const identityInitCodeHash = keccak256(identityInitCode);

  console.log("   Mining for vanity address starting with 0x8004a...");
  console.log("   (This may take a bit - typically ~500k attempts for 5-digit prefix)");
  const identityVanityResult = findVanitySalt(factory.address, identityInitCodeHash, "8004a");

  if (!identityVanityResult) {
    throw new Error("Could not find vanity address after maximum iterations");
  }

  console.log("   ✅ Found salt:", identityVanityResult.salt);
  console.log("   ✅ Predicted address:", identityVanityResult.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const identityDeployTx = await factory.write.deploy([identityVanityResult.salt, identityInitCode]);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  await publicClient.waitForTransactionReceipt({ hash: identityDeployTx });
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const identityProxy = await viem.getContractAt("ERC1967Proxy", identityVanityResult.address);
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
  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable", []);
  console.log("   Implementation deployed at:", reputationRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 4: Deploy ReputationRegistry Proxy with vanity address 0x8004b
  console.log("4. Deploying ReputationRegistry proxy with vanity address...");
  const reputationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxy.address]
  );
  const reputationInitData = ("0xc4d66de8" + reputationInitCalldata.slice(2)) as `0x${string}`;

  const reputationConstructorArgs = encodeAbiParameters(
    [{ type: "address" }, { type: "bytes" }],
    [reputationRegistryImpl.address, reputationInitData]
  );

  const reputationInitCode = (proxyBytecode + reputationConstructorArgs.slice(2)) as `0x${string}`;
  const reputationInitCodeHash = keccak256(reputationInitCode);

  console.log("   Mining for vanity address starting with 0x8004b...");
  const reputationVanityResult = findVanitySalt(factory.address, reputationInitCodeHash, "8004b");

  if (!reputationVanityResult) {
    throw new Error("Could not find vanity address for ReputationRegistry after maximum iterations");
  }

  console.log("   ✅ Found salt:", reputationVanityResult.salt);
  console.log("   ✅ Predicted address:", reputationVanityResult.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const reputationDeployTx = await factory.write.deploy([reputationVanityResult.salt, reputationInitCode]);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  await publicClient.waitForTransactionReceipt({ hash: reputationDeployTx });
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const reputationProxy = await viem.getContractAt("ERC1967Proxy", reputationVanityResult.address);
  console.log("   Proxy deployed at:", reputationProxy.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  const reputationRegistry = await viem.getContractAt(
    "ReputationRegistryUpgradeable",
    reputationProxy.address
  );

  // Step 5: Deploy ValidationRegistry Implementation
  console.log("5. Deploying ValidationRegistry implementation...");
  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable", []);
  console.log("   Implementation deployed at:", validationRegistryImpl.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  // Step 6: Deploy ValidationRegistry Proxy with vanity address 0x8004c
  console.log("6. Deploying ValidationRegistry proxy with vanity address...");
  const validationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxy.address]
  );
  const validationInitData = ("0xc4d66de8" + validationInitCalldata.slice(2)) as `0x${string}`;

  const validationConstructorArgs = encodeAbiParameters(
    [{ type: "address" }, { type: "bytes" }],
    [validationRegistryImpl.address, validationInitData]
  );

  const validationInitCode = (proxyBytecode + validationConstructorArgs.slice(2)) as `0x${string}`;
  const validationInitCodeHash = keccak256(validationInitCode);

  console.log("   Mining for vanity address starting with 0x8004c...");
  const validationVanityResult = findVanitySalt(factory.address, validationInitCodeHash, "8004c");

  if (!validationVanityResult) {
    throw new Error("Could not find vanity address for ValidationRegistry after maximum iterations");
  }

  console.log("   ✅ Found salt:", validationVanityResult.salt);
  console.log("   ✅ Predicted address:", validationVanityResult.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const validationDeployTx = await factory.write.deploy([validationVanityResult.salt, validationInitCode]);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  await publicClient.waitForTransactionReceipt({ hash: validationDeployTx });
  console.log("   Waiting 3 seconds...");
  await sleep(3000);

  const validationProxy = await viem.getContractAt("ERC1967Proxy", validationVanityResult.address);
  console.log("   Proxy deployed at:", validationProxy.address);
  console.log("   Waiting 3 seconds...");
  await sleep(3000);
  console.log("");

  const validationRegistry = await viem.getContractAt(
    "ValidationRegistryUpgradeable",
    validationProxy.address
  );

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
