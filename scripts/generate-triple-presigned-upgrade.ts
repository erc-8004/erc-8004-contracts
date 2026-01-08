import hre from "hardhat";
import { encodeFunctionData, Hex, parseGwei, keccak256, getCreate2Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import dotenv from "dotenv";
import fs from "fs";

// Load environment variables
dotenv.config();

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
 * Expected vanity proxy addresses
 */
const PROXIES = {
  identityRegistry: "0x8004A818BFB912233c491871b3d84c89A494BD9e",
  reputationRegistry: "0x8004B663056A597Dffe9eCcC1965A193B7388713",
  validationRegistry: "0x8004Cb1BF31DAf7788923b405b754f57acEB4272",
} as const;

/**
 * Generate 3 pre-signed upgrade transactions
 * Simple approach: one transaction per upgrade, sequential nonces
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const chainId = await publicClient.getChainId();

  console.log("=".repeat(80));
  console.log("Generating 3 Pre-Signed Upgrade Transactions");
  console.log("=".repeat(80));
  console.log("Chain ID:", chainId);
  console.log("");

  // Calculate implementation addresses via CREATE2
  const identityImplArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationImplArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationImplArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  const IMPLEMENTATIONS = {
    identityRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.identityRegistry,
      bytecodeHash: keccak256(identityImplArtifact.bytecode as Hex),
    }),
    reputationRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.reputationRegistry,
      bytecodeHash: keccak256(reputationImplArtifact.bytecode as Hex),
    }),
    validationRegistry: getCreate2Address({
      from: SAFE_SINGLETON_FACTORY,
      salt: IMPLEMENTATION_SALTS.validationRegistry,
      bytecodeHash: keccak256(validationImplArtifact.bytecode as Hex),
    }),
  };

  console.log("Implementation addresses (calculated via CREATE2):");
  console.log("  IdentityRegistry:  ", IMPLEMENTATIONS.identityRegistry);
  console.log("  ReputationRegistry:", IMPLEMENTATIONS.reputationRegistry);
  console.log("  ValidationRegistry:", IMPLEMENTATIONS.validationRegistry);
  console.log("");

  // Get owner private key
  let ownerPrivateKey = process.env.OWNER_PRIVATE_KEY;
  if (!ownerPrivateKey) {
    throw new Error("OWNER_PRIVATE_KEY not found in environment variables");
  }

  if (!ownerPrivateKey.startsWith("0x")) {
    ownerPrivateKey = `0x${ownerPrivateKey}`;
  }

  const ownerAccount = privateKeyToAccount(ownerPrivateKey as `0x${string}`);
  console.log("Owner address:", ownerAccount.address);
  console.log("");

  // Always use nonces 0, 1, 2 for production package
  // This assumes owner address is fresh (never used before)
  const startingNonce = 0;

  console.log("Generating transactions with nonces: 0, 1, 2");
  console.log("⚠️  Owner address must be fresh (never used) for these to work!");
  console.log("");

  // Get MinimalUUPS artifact for upgradeToAndCall
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");

  // Gas settings
  const gasPrice = parseGwei("20"); // 20 gwei

  // Encode initialize() calls for each implementation
  const identityInitData = encodeFunctionData({
    abi: identityImplArtifact.abi,
    functionName: "initialize",
    args: []
  });
  const reputationInitData = encodeFunctionData({
    abi: reputationImplArtifact.abi,
    functionName: "initialize",
    args: [PROXIES.identityRegistry]
  });
  const validationInitData = encodeFunctionData({
    abi: validationImplArtifact.abi,
    functionName: "initialize",
    args: [PROXIES.identityRegistry]
  });

  // Prepare all three transactions
  const transactions = [
    {
      name: "IdentityRegistry",
      proxy: PROXIES.identityRegistry,
      implementation: IMPLEMENTATIONS.identityRegistry,
      initData: identityInitData,
      nonce: startingNonce,
    },
    {
      name: "ReputationRegistry",
      proxy: PROXIES.reputationRegistry,
      implementation: IMPLEMENTATIONS.reputationRegistry,
      initData: reputationInitData,
      nonce: startingNonce + 1,
    },
    {
      name: "ValidationRegistry",
      proxy: PROXIES.validationRegistry,
      implementation: IMPLEMENTATIONS.validationRegistry,
      initData: validationInitData,
      nonce: startingNonce + 2,
    },
  ];

  const signedTransactions = [];

  for (const tx of transactions) {
    console.log(`Preparing ${tx.name} upgrade (nonce ${tx.nonce})...`);

    // Encode upgradeToAndCall with initialize() data
    const upgradeData = encodeFunctionData({
      abi: minimalUUPSArtifact.abi,
      functionName: "upgradeToAndCall",
      args: [tx.implementation, tx.initData],
    });

    // Estimate gas
    const gasEstimate = await publicClient.estimateGas({
      account: ownerAccount.address,
      to: tx.proxy as `0x${string}`,
      data: upgradeData,
    });

    // Add 30% buffer
    const gasLimit = (gasEstimate * 130n) / 100n;

    console.log(`  Gas estimate: ${gasEstimate.toString()}`);
    console.log(`  Gas limit (with 30% buffer): ${gasLimit.toString()}`);

    // Create and sign transaction
    const transaction = {
      to: tx.proxy as `0x${string}`,
      value: 0n,
      data: upgradeData,
      gas: gasLimit,
      gasPrice,
      nonce: tx.nonce,
      chainId,
    };

    const signature = await ownerAccount.signTransaction(transaction);

    const requiredFunding = gasLimit * gasPrice;

    signedTransactions.push({
      name: tx.name,
      proxy: tx.proxy,
      implementation: tx.implementation,
      nonce: tx.nonce,
      gasLimit: gasLimit.toString(),
      gasPrice: gasPrice.toString(),
      requiredFunding: requiredFunding.toString(),
      requiredFundingEth: (Number(requiredFunding) / 1e18).toFixed(6),
      signedTransaction: signature,
    });

    console.log(`  ✅ Signed`);
    console.log("");
  }

  // Calculate total funding needed
  const totalFunding = signedTransactions.reduce(
    (sum, tx) => sum + BigInt(tx.requiredFunding),
    0n
  );

  // Prepare output
  const output = {
    chainId,
    ownerAddress: ownerAccount.address,
    startingNonce,
    gasPrice: gasPrice.toString(),
    gasPriceGwei: Number(gasPrice) / 1e9,
    transactions: signedTransactions,
    totalFunding: totalFunding.toString(),
    totalFundingEth: (Number(totalFunding) / 1e18).toFixed(6),
    timestamp: new Date().toISOString(),
  };

  // Save to JSON
  const outputPath = `triple-presigned-upgrade-chain-${chainId}.json`;
  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));

  console.log("=".repeat(80));
  console.log("✅ All 3 Transactions Signed");
  console.log("=".repeat(80));
  console.log("");
  console.log("Output saved to:", outputPath);
  console.log("");
  console.log("📦 PACKAGE:");
  console.log("  Transaction 1 (nonce", startingNonce + "):", "IdentityRegistry upgrade");
  console.log("  Transaction 2 (nonce", startingNonce + 1 + "):", "ReputationRegistry upgrade");
  console.log("  Transaction 3 (nonce", startingNonce + 2 + "):", "ValidationRegistry upgrade");
  console.log("");
  console.log("  Total funding needed:", output.totalFundingEth, "ETH");
  console.log("  Owner address:", ownerAccount.address);
  console.log("");
  console.log("📋 TO BROADCAST:");
  console.log("  npx hardhat run scripts/broadcast-triple-presigned-upgrade.ts --network <network>");
  console.log("");
  console.log("=".repeat(80));

  return output;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
