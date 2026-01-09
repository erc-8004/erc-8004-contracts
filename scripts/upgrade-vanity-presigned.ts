import hre from "hardhat";
import { Hex, keccak256, getCreate2Address } from "viem";
import fs from "fs";

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
 * Upgrade vanity proxies using PRE-EXISTING pre-signed transactions
 *
 * IMPORTANT: This script does NOT generate signatures!
 * Pre-signed transactions must already exist in triple-presigned-upgrade-chain-{chainId}.json
 *
 * To generate pre-signed transactions first:
 *   npx hardhat run scripts/generate-triple-presigned-upgrade.ts --network <network>
 *
 * This script only loads and broadcasts the existing signatures.
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();
  const chainId = await publicClient.getChainId();

  console.log("=".repeat(80));
  console.log("Upgrading ERC-8004 Vanity Proxies (Pre-Signed Transactions)");
  console.log("=".repeat(80));
  console.log("Chain ID:", chainId);
  console.log("Deployer:", deployer.account.address);
  console.log("");

  // Calculate implementation addresses via CREATE2
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  const identityImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.identityRegistry,
    bytecodeHash: keccak256(identityImplArtifact.bytecode as Hex),
  });
  const reputationImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.reputationRegistry,
    bytecodeHash: keccak256(reputationImplArtifact.bytecode as Hex),
  });
  const validationImplAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: IMPLEMENTATION_SALTS.validationRegistry,
    bytecodeHash: keccak256(validationImplArtifact.bytecode as Hex),
  });

  // Expected contracts with calculated implementation addresses
  const EXPECTED_IMPLEMENTATIONS = {
    "0x8004A818BFB912233c491871b3d84c89A494BD9e": {
      name: "IdentityRegistry",
      implementation: identityImplAddress,
    },
    "0x8004B663056A597Dffe9eCcC1965A193B7388713": {
      name: "ReputationRegistry",
      implementation: reputationImplAddress,
    },
    "0x8004Cb1BF31DAf7788923b405b754f57acEB4272": {
      name: "ValidationRegistry",
      implementation: validationImplAddress,
    },
  };

  // ============================================================================
  // STEP 1: Check if contracts are deployed
  // ============================================================================

  console.log("STEP 1: Checking Contract Deployment Status");
  console.log("=".repeat(80));
  console.log("");

  console.log("Checking proxies...");
  for (const [proxyAddress, info] of Object.entries(EXPECTED_IMPLEMENTATIONS)) {
    const proxyCode = await publicClient.getBytecode({ address: proxyAddress as `0x${string}` });

    if (!proxyCode || proxyCode === "0x") {
      throw new Error(
        `❌ ${info.name} proxy not deployed!\n` +
        `\n` +
        `Expected proxy at: ${proxyAddress}\n` +
        `\n` +
        `Please run the deployment script first:\n` +
        `  npm run local:deploy:vanity`
      );
    }
    console.log(`  ✅ ${info.name} proxy deployed at ${proxyAddress}`);
  }

  console.log("");
  console.log("Checking implementations...");
  for (const [proxyAddress, info] of Object.entries(EXPECTED_IMPLEMENTATIONS)) {
    const implCode = await publicClient.getBytecode({ address: info.implementation as `0x${string}` });

    if (!implCode || implCode === "0x") {
      throw new Error(
        `❌ ${info.name} implementation not deployed!\n` +
        `\n` +
        `Expected implementation at: ${info.implementation}\n` +
        `\n` +
        `Please run the deployment script first:\n` +
        `  npm run local:deploy:vanity`
      );
    }
    console.log(`  ✅ ${info.name} implementation deployed at ${info.implementation}`);
  }

  console.log("");
  console.log("✅ All contracts are deployed");
  console.log("");

  // ============================================================================
  // STEP 2: Check if already upgraded
  // ============================================================================

  console.log("STEP 2: Checking Current Implementation Status");
  console.log("=".repeat(80));
  console.log("");

  const implSlot = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  let allUpgraded = true;

  for (const [proxyAddress, info] of Object.entries(EXPECTED_IMPLEMENTATIONS)) {
    const implStorage = await publicClient.getStorageAt({
      address: proxyAddress as `0x${string}`,
      slot: implSlot as `0x${string}`,
    });

    const currentImpl = implStorage ? `0x${implStorage.slice(-40)}` : null;

    if (!currentImpl || currentImpl === "0x0000000000000000000000000000000000000000") {
      throw new Error(
        `❌ ${info.name} proxy is not initialized!\n` +
        `\n` +
        `Proxy at ${proxyAddress} has no implementation set.\n` +
        `Please run the deployment script first:\n` +
        `  npm run local:deploy:vanity`
      );
    }

    const isUpgraded = currentImpl.toLowerCase() === info.implementation.toLowerCase();

    console.log(`${info.name}:`);
    console.log(`  Proxy: ${proxyAddress}`);
    console.log(`  Current implementation: ${currentImpl}`);
    console.log(`  Expected implementation: ${info.implementation}`);
    console.log(`  Status: ${isUpgraded ? "✅ Already upgraded" : "⚠️  Needs upgrade"}`);
    console.log("");

    if (!isUpgraded) {
      allUpgraded = false;
    }
  }

  if (allUpgraded) {
    console.log("=".repeat(80));
    console.log("✅ ALL PROXIES ALREADY UPGRADED");
    console.log("=".repeat(80));
    console.log("");
    console.log("All three proxies are already using the final implementations.");
    console.log("No upgrade needed. Skipping everything.");
    console.log("");
    return;
  }

  console.log("⚠️  Some proxies need upgrading. Checking for pre-signed transactions...");
  console.log("");

  // ============================================================================
  // STEP 3: Load pre-signed transactions (only if upgrade needed)
  // ============================================================================

  console.log("STEP 3: Loading Pre-Signed Transactions");
  console.log("=".repeat(80));

  const packagePath = `triple-presigned-upgrade-chain-${chainId}.json`;

  if (!fs.existsSync(packagePath)) {
    throw new Error(
      `❌ Pre-signed transactions not found!\n` +
      `\n` +
      `Expected file: ${packagePath}\n` +
      `\n` +
      `Please generate pre-signed transactions first:\n` +
      `  npx hardhat run scripts/generate-triple-presigned-upgrade.ts --network localhost\n` +
      `\n` +
      `The pre-signed transactions must be generated BEFORE running this script.`
    );
  }

  console.log("Loading from:", packagePath);
  const packageData = JSON.parse(fs.readFileSync(packagePath, "utf-8"));

  console.log("");
  console.log("Package Details:");
  console.log("  Owner:", packageData.ownerAddress);
  console.log("  Starting nonce:", packageData.startingNonce);
  console.log("  Transactions:", packageData.transactions.length);
  console.log("  Total funding:", packageData.totalFundingEth, "ETH");
  console.log("  Generated:", packageData.timestamp);
  console.log("");

  // Verify chain ID
  if (packageData.chainId !== chainId) {
    throw new Error(
      `Chain ID mismatch!\n` +
      `  Pre-signed package: ${packageData.chainId}\n` +
      `  Current chain: ${chainId}`
    );
  }

  const signedTransactions = packageData.transactions;
  const ownerAddress = packageData.ownerAddress as `0x${string}`;
  const totalFunding = BigInt(packageData.totalFunding);

  console.log("✅ Pre-signed transactions loaded successfully");
  console.log("");

  // ============================================================================
  // STEP 4: Fund owner and broadcast
  // ============================================================================

  console.log("STEP 4: Broadcasting Pre-Signed Transactions");
  console.log("=".repeat(80));

  console.log("Total funding needed:", packageData.totalFundingEth, "ETH");
  console.log("");

  // Check owner's balance
  const ownerBalance = await publicClient.getBalance({ address: ownerAddress });
  console.log("Current owner balance:", (Number(ownerBalance) / 1e18).toFixed(6), "ETH");

  // Fund owner if needed
  if (ownerBalance < totalFunding) {
    const fundingNeeded = totalFunding - ownerBalance;
    console.log("Funding owner with:", (Number(fundingNeeded) / 1e18).toFixed(6), "ETH");

    const fundTxHash = await deployer.sendTransaction({
      to: ownerAddress,
      value: fundingNeeded,
      gas: 21000n,
    });

    await publicClient.waitForTransactionReceipt({ hash: fundTxHash });
    console.log("✅ Owner funded");
  } else {
    console.log("✅ Owner has sufficient balance");
  }

  console.log("");

  // Verify starting nonce
  const currentNonce = await publicClient.getTransactionCount({ address: ownerAddress });
  if (currentNonce !== packageData.startingNonce) {
    throw new Error(
      `❌ Nonce mismatch!\n` +
      `  Pre-signed transactions expect nonce: ${packageData.startingNonce}\n` +
      `  Current owner nonce: ${currentNonce}\n` +
      `\n` +
      `The owner address may have been used for other transactions.`
    );
  }

  // Broadcast all transactions
  console.log("Broadcasting transactions...");
  console.log("");

  const txHashes = [];

  for (const tx of signedTransactions) {
    console.log(`Broadcasting ${tx.name} upgrade...`);

    const txHash = await publicClient.sendRawTransaction({
      serializedTransaction: tx.signedTransaction as Hex,
    });

    console.log(`  Transaction: ${txHash}`);
    txHashes.push({ name: tx.name, hash: txHash, proxy: tx.proxy, implementation: tx.implementation });
  }

  console.log("");

  // Wait for confirmations
  console.log("Waiting for confirmations...");
  console.log("");

  for (const { name, hash } of txHashes) {
    console.log(`Confirming ${name}...`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    console.log(`  Block: ${receipt.blockNumber}`);
    console.log(`  Gas used: ${receipt.gasUsed.toString()}`);
    console.log(`  Status: ${receipt.status === "success" ? "✅ SUCCESS" : "❌ FAILED"}`);

    if (receipt.status !== "success") {
      throw new Error(`${name} upgrade failed!`);
    }
  }

  console.log("");

  // Verify upgrades
  console.log("STEP 5: Verifying Upgrades");
  console.log("=".repeat(80));
  console.log("");

  for (const tx of txHashes) {
    const implStorage = await publicClient.getStorageAt({
      address: tx.proxy as `0x${string}`,
      slot: implSlot as `0x${string}`,
    });

    const currentImpl = implStorage ? `0x${implStorage.slice(-40)}` : null;
    const match = currentImpl?.toLowerCase() === tx.implementation.toLowerCase();

    console.log(`${tx.name}:`);
    console.log(`  Current implementation: ${currentImpl}`);
    console.log(`  Expected: ${tx.implementation}`);
    console.log(`  Status: ${match ? "✅ VERIFIED" : "❌ MISMATCH"}`);
    console.log("");

    if (!match) {
      throw new Error(`${tx.name} verification failed!`);
    }
  }

  console.log("=".repeat(80));
  console.log("✅ ALL UPGRADES COMPLETED SUCCESSFULLY");
  console.log("=".repeat(80));
  console.log("");
  console.log("All three proxies upgraded:");
  console.log("  ✅ IdentityRegistry");
  console.log("  ✅ ReputationRegistry");
  console.log("  ✅ ValidationRegistry");
  console.log("");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
