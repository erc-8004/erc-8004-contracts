import hre from "hardhat";
import { createPublicClient, createWalletClient, http, getContract, encodeDeployData, keccak256, concat, pad, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Target vanity prefixes (case-insensitive)
const VANITY_PREFIXES = {
  identityRegistry: "0x8004a",
  reputationRegistry: "0x8004b",
  validationRegistry: "0x8004c",
};

/**
 * Calculate CREATE2 address deterministically
 */
function calculateCreate2Address(
  factoryAddress: `0x${string}`,
  salt: `0x${string}`,
  initCodeHash: `0x${string}`
): `0x${string}` {
  const data = concat([
    "0xff",
    factoryAddress,
    salt,
    initCodeHash,
  ]);
  const hash = keccak256(data);
  // Take last 20 bytes (40 hex chars) for address
  return `0x${hash.slice(-40)}` as `0x${string}`;
}

/**
 * Mine a salt deterministically to find a vanity address
 * Starts from 0 and increments - always produces same result
 */
function mineSalt(
  factoryAddress: `0x${string}`,
  initCodeHash: `0x${string}`,
  prefix: string
): { salt: `0x${string}`; address: `0x${string}`; iterations: number } {
  console.log(`\n🔍 Mining salt for prefix: ${prefix}`);
  const startTime = Date.now();

  // Start from 0 and increment deterministically
  for (let i = 0; i < 100_000_000; i++) {
    const salt = pad(toHex(i), { size: 32 });
    const address = calculateCreate2Address(factoryAddress, salt, initCodeHash);

    // Check if address matches prefix (case-insensitive)
    if (address.toLowerCase().startsWith(prefix.toLowerCase())) {
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      console.log(`✅ Found in ${duration}s after ${i.toLocaleString()} iterations`);
      console.log(`   Salt: ${salt}`);
      console.log(`   Address: ${address}`);
      return { salt, address, iterations: i };
    }

    // Progress indicator every 100k iterations
    if (i > 0 && i % 100_000 === 0) {
      process.stdout.write(`\r   Tried ${i.toLocaleString()} salts...`);
    }
  }

  throw new Error(`Failed to find vanity address after 100M iterations`);
}

/**
 * Check if contract is already deployed at address
 */
async function isContractDeployed(client: any, address: `0x${string}`): Promise<boolean> {
  const code = await client.getBytecode({ address });
  return code !== undefined && code !== "0x";
}

async function main() {
  console.log("🚀 Starting Vanity Address Mining & Deployment");
  console.log("=" .repeat(60));

  // Setup clients
  const account = privateKeyToAccount(hre.network.config.accounts[0] as `0x${string}`);

  const publicClient = createPublicClient({
    chain: hre.network.config,
    transport: http(),
  });

  const walletClient = createWalletClient({
    account,
    chain: hre.network.config,
    transport: http(),
  });

  // Step 1: Use SAFE Singleton Factory (ERC-2470)
  console.log("\n📦 Step 1: Using SAFE Singleton Factory");
  console.log("-".repeat(60));

  // SAFE Singleton Factory is deployed at this address on all EVM chains
  const factoryAddress: `0x${string}` = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7";

  // Check if factory exists at this address
  const factoryCode = await publicClient.getBytecode({ address: factoryAddress });
  if (!factoryCode || factoryCode === "0x") {
    console.log("❌ SAFE Singleton Factory not found at", factoryAddress);
    console.log("   This chain may not have the factory pre-deployed.");
    console.log("   You can deploy it following: https://github.com/safe-global/safe-singleton-factory");
    throw new Error("SAFE Singleton Factory not deployed on this chain");
  }

  console.log(`✅ SAFE Singleton Factory found at: ${factoryAddress}`);

  // Get the factory ABI (same interface as our SingletonFactory)
  const SingletonFactory = await hre.viem.getContractFactory("SingletonFactory");

  // Step 2: Compile contracts and prepare bytecode
  console.log("\n📝 Step 2: Preparing Contract Bytecode");
  console.log("-".repeat(60));

  // Get implementation contracts
  const IdentityRegistryImpl = await hre.viem.getContractFactory("IdentityRegistryUpgradeable");
  const ReputationRegistryImpl = await hre.viem.getContractFactory("ReputationRegistryUpgradeable");
  const ValidationRegistryImpl = await hre.viem.getContractFactory("ValidationRegistryUpgradeable");
  const ProxyFactory = await hre.viem.getContractFactory("ERC1967Proxy");

  console.log("✅ All contracts compiled");

  // Step 3: Deploy implementations (addresses don't matter)
  console.log("\n🏗️  Step 3: Deploying Implementation Contracts");
  console.log("-".repeat(60));

  console.log("Deploying IdentityRegistryUpgradeable implementation...");
  const identityImpl = await hre.viem.deployContract("IdentityRegistryUpgradeable");
  console.log(`✅ IdentityRegistry impl: ${identityImpl.address}`);

  console.log("Deploying ReputationRegistryUpgradeable implementation...");
  const reputationImpl = await hre.viem.deployContract("ReputationRegistryUpgradeable");
  console.log(`✅ ReputationRegistry impl: ${reputationImpl.address}`);

  console.log("Deploying ValidationRegistryUpgradeable implementation...");
  const validationImpl = await hre.viem.deployContract("ValidationRegistryUpgradeable");
  console.log(`✅ ValidationRegistry impl: ${validationImpl.address}`);

  // Step 4: Mine vanity salts for proxies
  console.log("\n⛏️  Step 4: Mining Vanity Salts for Proxies");
  console.log("-".repeat(60));

  // Prepare proxy init codes (with implementation addresses as constructor args)
  const identityProxyInitCode = encodeDeployData({
    abi: ProxyFactory.abi,
    bytecode: ProxyFactory.bytecode,
    args: [identityImpl.address, "0x"],
  });

  const reputationProxyInitCode = encodeDeployData({
    abi: ProxyFactory.abi,
    bytecode: ProxyFactory.bytecode,
    args: [reputationImpl.address, "0x"],
  });

  const validationProxyInitCode = encodeDeployData({
    abi: ProxyFactory.abi,
    bytecode: ProxyFactory.bytecode,
    args: [validationImpl.address, "0x"],
  });

  // Calculate init code hashes
  const identityProxyInitHash = keccak256(identityProxyInitCode);
  const reputationProxyInitHash = keccak256(reputationProxyInitCode);
  const validationProxyInitHash = keccak256(validationProxyInitCode);

  // Mine salts
  console.log("\n🎯 Mining IdentityRegistry proxy salt...");
  const identitySalt = mineSalt(factoryAddress, identityProxyInitHash, VANITY_PREFIXES.identityRegistry);

  console.log("\n🎯 Mining ReputationRegistry proxy salt...");
  const reputationSalt = mineSalt(factoryAddress, reputationProxyInitHash, VANITY_PREFIXES.reputationRegistry);

  console.log("\n🎯 Mining ValidationRegistry proxy salt...");
  const validationSalt = mineSalt(factoryAddress, validationProxyInitHash, VANITY_PREFIXES.validationRegistry);

  // Step 5: Deploy proxies with vanity addresses
  console.log("\n🎨 Step 5: Deploying Proxies with Vanity Addresses");
  console.log("-".repeat(60));

  const factoryContract = getContract({
    address: factoryAddress,
    abi: SingletonFactory.abi,
    client: { public: publicClient, wallet: walletClient },
  });

  // Deploy Identity Registry Proxy
  console.log("\n📍 Deploying IdentityRegistry proxy...");
  const identityExpectedAddress = identitySalt.address;

  // Check if already deployed
  if (await isContractDeployed(publicClient, identityExpectedAddress)) {
    console.log(`⚠️  Proxy already exists at ${identityExpectedAddress}, skipping...`);
  } else {
    try {
      const identityHash = await factoryContract.write.deploy([identityProxyInitCode, identitySalt.salt]);
      await publicClient.waitForTransactionReceipt({ hash: identityHash });
      console.log(`✅ IdentityRegistry proxy deployed: ${identityExpectedAddress}`);
    } catch (error: any) {
      console.error(`❌ Failed to deploy IdentityRegistry proxy: ${error.message}`);
      console.log(`   Expected address: ${identityExpectedAddress}`);
      console.log(`   You can retry with the same salt: ${identitySalt.salt}`);
      throw error;
    }
  }

  // Deploy Reputation Registry Proxy
  console.log("\n📍 Deploying ReputationRegistry proxy...");
  const reputationExpectedAddress = reputationSalt.address;

  if (await isContractDeployed(publicClient, reputationExpectedAddress)) {
    console.log(`⚠️  Proxy already exists at ${reputationExpectedAddress}, skipping...`);
  } else {
    try {
      const reputationHash = await factoryContract.write.deploy([reputationProxyInitCode, reputationSalt.salt]);
      await publicClient.waitForTransactionReceipt({ hash: reputationHash });
      console.log(`✅ ReputationRegistry proxy deployed: ${reputationExpectedAddress}`);
    } catch (error: any) {
      console.error(`❌ Failed to deploy ReputationRegistry proxy: ${error.message}`);
      console.log(`   Expected address: ${reputationExpectedAddress}`);
      console.log(`   You can retry with the same salt: ${reputationSalt.salt}`);
      throw error;
    }
  }

  // Deploy Validation Registry Proxy
  console.log("\n📍 Deploying ValidationRegistry proxy...");
  const validationExpectedAddress = validationSalt.address;

  if (await isContractDeployed(publicClient, validationExpectedAddress)) {
    console.log(`⚠️  Proxy already exists at ${validationExpectedAddress}, skipping...`);
  } else {
    try {
      const validationHash = await factoryContract.write.deploy([validationProxyInitCode, validationSalt.salt]);
      await publicClient.waitForTransactionReceipt({ hash: validationHash });
      console.log(`✅ ValidationRegistry proxy deployed: ${validationExpectedAddress}`);
    } catch (error: any) {
      console.error(`❌ Failed to deploy ValidationRegistry proxy: ${error.message}`);
      console.log(`   Expected address: ${validationExpectedAddress}`);
      console.log(`   You can retry with the same salt: ${validationSalt.salt}`);
      throw error;
    }
  }

  // Step 6: Initialize proxies
  console.log("\n⚙️  Step 6: Initializing Proxies");
  console.log("-".repeat(60));

  // Initialize IdentityRegistry
  console.log("Initializing IdentityRegistry...");
  const identityProxy = await hre.viem.getContractAt("IdentityRegistryUpgradeable", identityExpectedAddress);
  try {
    const initHash1 = await identityProxy.write.initialize([
      account.address,
      "ERC8004 Identity",
      "ERC8004ID",
    ]);
    await publicClient.waitForTransactionReceipt({ hash: initHash1 });
    console.log("✅ IdentityRegistry initialized");
  } catch (error: any) {
    if (error.message.includes("already initialized") || error.message.includes("Initializable")) {
      console.log("⚠️  Already initialized, skipping...");
    } else {
      throw error;
    }
  }

  // Initialize ReputationRegistry
  console.log("Initializing ReputationRegistry...");
  const reputationProxy = await hre.viem.getContractAt("ReputationRegistryUpgradeable", reputationExpectedAddress);
  try {
    const initHash2 = await reputationProxy.write.initialize([
      account.address,
      identityExpectedAddress,
    ]);
    await publicClient.waitForTransactionReceipt({ hash: initHash2 });
    console.log("✅ ReputationRegistry initialized");
  } catch (error: any) {
    if (error.message.includes("already initialized") || error.message.includes("Initializable")) {
      console.log("⚠️  Already initialized, skipping...");
    } else {
      throw error;
    }
  }

  // Initialize ValidationRegistry
  console.log("Initializing ValidationRegistry...");
  const validationProxy = await hre.viem.getContractAt("ValidationRegistryUpgradeable", validationExpectedAddress);
  try {
    const initHash3 = await validationProxy.write.initialize([
      account.address,
      identityExpectedAddress,
    ]);
    await publicClient.waitForTransactionReceipt({ hash: initHash3 });
    console.log("✅ ValidationRegistry initialized");
  } catch (error: any) {
    if (error.message.includes("already initialized") || error.message.includes("Initializable")) {
      console.log("⚠️  Already initialized, skipping...");
    } else {
      throw error;
    }
  }

  // Final summary
  console.log("\n" + "=".repeat(60));
  console.log("🎉 DEPLOYMENT COMPLETE");
  console.log("=".repeat(60));
  console.log("\n📋 Summary:");
  console.log(`\nSingletonFactory: ${factoryAddress}`);
  console.log("\nImplementations:");
  console.log(`  IdentityRegistry:   ${identityImpl.address}`);
  console.log(`  ReputationRegistry: ${reputationImpl.address}`);
  console.log(`  ValidationRegistry: ${validationImpl.address}`);
  console.log("\n🎨 Vanity Address Proxies:");
  console.log(`  IdentityRegistry:   ${identityExpectedAddress}`);
  console.log(`  ReputationRegistry: ${reputationExpectedAddress}`);
  console.log(`  ValidationRegistry: ${validationExpectedAddress}`);
  console.log("\n🔑 Salts (save these for other chains):");
  console.log(`  IdentityRegistry:   ${identitySalt.salt}`);
  console.log(`  ReputationRegistry: ${reputationSalt.salt}`);
  console.log(`  ValidationRegistry: ${validationSalt.salt}`);
  console.log("\n" + "=".repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });
