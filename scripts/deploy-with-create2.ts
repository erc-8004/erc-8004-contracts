import { createPublicClient, createWalletClient, http, defineChain, encodeAbiParameters, getContract, keccak256, pad, toHex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import { join } from "path";

/**
 * FINAL DEPLOYMENT: Deploy our own CREATE2 factory and use it for vanity addresses
 */

const zeroGNewton = defineChain({
  id: 16602,
  name: '0G Newton Testnet',
  nativeCurrency: { decimals: 18, name: '0G', symbol: 'A0GI' },
  rpcUrls: { default: { http: ['https://evmrpc-testnet.0g.ai'] } },
  blockExplorers: { default: { name: '0G Explorer', url: 'https://chainscan-newton.0g.ai' } },
  testnet: true,
});

const IMPLEMENTATIONS = {
  identity: "0x0c342a7342237976236819b3160f9d7ea8c23ac6" as `0x${string}`,
  reputation: "0x363a785f1c83d375f275fb121ee8087b7e31f5c4" as `0x${string}`,
  validation: "0x6251598b4fe45dcadfd2e6dc42b007498073af4a" as `0x${string}`,
};

function loadArtifact(contractName: string) {
  const artifactPath = join(process.cwd(), `artifacts/contracts/${contractName}.sol/${contractName}.json`);
  return JSON.parse(readFileSync(artifactPath, 'utf8'));
}

function computeCreate2Address(factoryAddr: `0x${string}`, salt: `0x${string}`, bytecode: `0x${string}`): `0x${string}` {
  const initCodeHash = keccak256(bytecode);
  const data = `0xff${factoryAddr.slice(2)}${salt.slice(2)}${initCodeHash.slice(2)}`;
  const hash = keccak256(data as `0x${string}`);
  return `0x${hash.slice(-40)}` as `0x${string}`;
}

function mineSalt(factoryAddr: `0x${string}`, bytecode: `0x${string}`, prefix: string = "8004", maxAttempts: number = 5000000) {
  console.log(`   Mining for 0x${prefix}...`);
  const startTime = Date.now();
  
  for (let i = 0; i < maxAttempts; i++) {
    const salt = pad(toHex(i), { size: 32 });
    const address = computeCreate2Address(factoryAddr, salt, bytecode);
    
    if (address.toLowerCase().startsWith(`0x${prefix.toLowerCase()}`)) {
      const elapsed = Date.now() - startTime;
      console.log(`   ✅ Found in ${(elapsed / 1000).toFixed(1)}s! (${i + 1} attempts)`);
      return { salt, address };
    }
    
    if (i % 50000 === 0 && i > 0) {
      console.log(`   Checked ${i.toLocaleString()}...`);
    }
  }
  
  return null;
}

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("     FINAL 0x8004 VANITY DEPLOYMENT - Own CREATE2 Factory      ");
  console.log("═══════════════════════════════════════════════════════════════\n");

  const privateKeyEnv = process.env.ZEROG_PRIVATE_KEY;
  if (!privateKeyEnv) throw new Error("ZEROG_PRIVATE_KEY not set");

  const privateKey = (privateKeyEnv.startsWith('0x') ? privateKeyEnv : `0x${privateKeyEnv}`) as `0x${string}`;
  const account = privateKeyToAccount(privateKey);

  const publicClient = createPublicClient({ chain: zeroGNewton, transport: http() });
  const walletClient = createWalletClient({ account, chain: zeroGNewton, transport: http() });

  console.log("Deployer:", account.address);
  const balance = await publicClient.getBalance({ address: account.address });
  console.log("Balance:", (Number(balance) / 1e18).toFixed(6), "A0GI\n");

  // Step 1: Deploy CREATE2 Factory
  console.log("Step 1: Deploying CREATE2 Factory");
  console.log("───────────────────────────────────────────────────────────────");
  
  const FactoryArtifact = loadArtifact("Create2Factory");
  const factoryHash = await walletClient.deployContract({
    abi: FactoryArtifact.abi,
    bytecode: FactoryArtifact.bytecode as `0x${string}`,
    account,
  });
  
  console.log("TX:", factoryHash);
  const factoryReceipt = await publicClient.waitForTransactionReceipt({ hash: factoryHash });
  const factoryAddress = factoryReceipt.contractAddress!;
  console.log("✅ Factory deployed at:", factoryAddress);
  console.log("");

  const factory = getContract({
    address: factoryAddress,
    abi: FactoryArtifact.abi,
    client: { public: publicClient, wallet: walletClient },
  });

  const ProxyArtifact = loadArtifact("ERC1967Proxy");

  // Step 2: Mine salt and deploy Identity Proxy
  console.log("Step 2: IdentityRegistry Proxy (mining salt...)");
  console.log("───────────────────────────────────────────────────────────────");
  
  const identityInitCalldata = "0x8129fc1c" as `0x${string}`;
  const identityConstructorArgs = encodeAbiParameters(
    [{ name: "implementation", type: "address" }, { name: "data", type: "bytes" }],
    [IMPLEMENTATIONS.identity, identityInitCalldata]
  );
  const identityProxyBytecode = `${ProxyArtifact.bytecode}${identityConstructorArgs.slice(2)}` as `0x${string}`;
  
  const identityMined = mineSalt(factoryAddress, identityProxyBytecode, "8004");
  if (!identityMined) {
    console.log("❌ Failed to find salt!");
    return;
  }
  
  console.log(`   Salt: ${identityMined.salt}`);
  console.log(`   Expected address: ${identityMined.address}`);
  console.log("\n   Deploying...");
  
  const identityTx = await factory.write.deploy([identityMined.salt, identityProxyBytecode]);
  console.log("   TX:", identityTx);
  await publicClient.waitForTransactionReceipt({ hash: identityTx });
  
  const identityCode = await publicClient.getCode({ address: identityMined.address });
  if (!identityCode || identityCode === '0x') {
    console.log("   ❌ Deployment failed!");
    return;
  }
  console.log("   ✅ Deployed at:", identityMined.address);
  console.log("");

  // Step 3: Mine salt and deploy Reputation Proxy
  console.log("Step 3: ReputationRegistry Proxy (mining salt...)");
  console.log("───────────────────────────────────────────────────────────────");
  
  const reputationInitData = `0xc4d66de8${identityMined.address.slice(2).padStart(64, '0')}` as `0x${string}`;
  const reputationConstructorArgs = encodeAbiParameters(
    [{ name: "implementation", type: "address" }, { name: "data", type: "bytes" }],
    [IMPLEMENTATIONS.reputation, reputationInitData]
  );
  const reputationProxyBytecode = `${ProxyArtifact.bytecode}${reputationConstructorArgs.slice(2)}` as `0x${string}`;
  
  const reputationMined = mineSalt(factoryAddress, reputationProxyBytecode, "8004");
  if (!reputationMined) {
    console.log("❌ Failed to find salt!");
    return;
  }
  
  console.log(`   Salt: ${reputationMined.salt}`);
  console.log(`   Expected address: ${reputationMined.address}`);
  console.log("\n   Deploying...");
  
  const reputationTx = await factory.write.deploy([reputationMined.salt, reputationProxyBytecode]);
  console.log("   TX:", reputationTx);
  await publicClient.waitForTransactionReceipt({ hash: reputationTx });
  
  const reputationCode = await publicClient.getCode({ address: reputationMined.address });
  if (!reputationCode || reputationCode === '0x') {
    console.log("   ❌ Deployment failed!");
    return;
  }
  console.log("   ✅ Deployed at:", reputationMined.address);
  console.log("");

  // Step 4: Mine salt and deploy Validation Proxy
  console.log("Step 4: ValidationRegistry Proxy (mining salt...)");
  console.log("───────────────────────────────────────────────────────────────");
  
  const validationInitData = `0xc4d66de8${identityMined.address.slice(2).padStart(64, '0')}` as `0x${string}`;
  const validationConstructorArgs = encodeAbiParameters(
    [{ name: "implementation", type: "address" }, { name: "data", type: "bytes" }],
    [IMPLEMENTATIONS.validation, validationInitData]
  );
  const validationProxyBytecode = `${ProxyArtifact.bytecode}${validationConstructorArgs.slice(2)}` as `0x${string}`;
  
  const validationMined = mineSalt(factoryAddress, validationProxyBytecode, "8004");
  if (!validationMined) {
    console.log("❌ Failed to find salt!");
    return;
  }
  
  console.log(`   Salt: ${validationMined.salt}`);
  console.log(`   Expected address: ${validationMined.address}`);
  console.log("\n   Deploying...");
  
  const validationTx = await factory.write.deploy([validationMined.salt, validationProxyBytecode]);
  console.log("   TX:", validationTx);
  await publicClient.waitForTransactionReceipt({ hash: validationTx });
  
  const validationCode = await publicClient.getCode({ address: validationMined.address });
  if (!validationCode || validationCode === '0x') {
    console.log("   ❌ Deployment failed!");
    return;
  }
  console.log("   ✅ Deployed at:", validationMined.address);
  console.log("");

  // Verification
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("                   VERIFYING DEPLOYMENTS                       ");
  console.log("═══════════════════════════════════════════════════════════════\n");

  const IdentityArtifact = loadArtifact("IdentityRegistryUpgradeable");
  const ReputationArtifact = loadArtifact("ReputationRegistryUpgradeable");
  const ValidationArtifact = loadArtifact("ValidationRegistryUpgradeable");

  const identity = getContract({
    address: identityMined.address,
    abi: IdentityArtifact.abi,
    client: publicClient,
  });

  const reputation = getContract({
    address: reputationMined.address,
    abi: ReputationArtifact.abi,
    client: publicClient,
  });

  const validation = getContract({
    address: validationMined.address,
    abi: ValidationArtifact.abi,
    client: publicClient,
  });

  const identityVersion = await identity.read.getVersion();
  console.log("IdentityRegistry version:", identityVersion);

  const reputationVersion = await reputation.read.getVersion();
  const reputationIdentityRegistry = await reputation.read.getIdentityRegistry();
  console.log("ReputationRegistry version:", reputationVersion);
  console.log("ReputationRegistry identityRegistry:", reputationIdentityRegistry);

  const validationVersion = await validation.read.getVersion();
  const validationIdentityRegistry = await validation.read.getIdentityRegistry();
  console.log("ValidationRegistry version:", validationVersion);
  console.log("ValidationRegistry identityRegistry:", validationIdentityRegistry);

  // Final Summary
  console.log("\n\n═══════════════════════════════════════════════════════════════");
  console.log("            🎉 CANONICAL DEPLOYMENT COMPLETE! 🎉               ");
  console.log("═══════════════════════════════════════════════════════════════\n");

  console.log("✅ ALL ADDRESSES START WITH 0x8004:\n");
  console.log("IdentityRegistry:    ", identityMined.address);
  console.log("ReputationRegistry:  ", reputationMined.address);
  console.log("ValidationRegistry:  ", validationMined.address);
  console.log("");

  console.log("📝 CREATE2 Factory:    ", factoryAddress);
  console.log("");

  console.log("📝 Implementation Addresses:");
  console.log("IdentityRegistry:    ", IMPLEMENTATIONS.identity);
  console.log("ReputationRegistry:  ", IMPLEMENTATIONS.reputation);
  console.log("ValidationRegistry:  ", IMPLEMENTATIONS.validation);
  console.log("");

  console.log("🔗 Explorer Links:");
  console.log(`Identity:    https://chainscan-newton.0g.ai/address/${identityMined.address}`);
  console.log(`Reputation:  https://chainscan-newton.0g.ai/address/${reputationMined.address}`);
  console.log(`Validation:  https://chainscan-newton.0g.ai/address/${validationMined.address}`);
  console.log("");

  console.log("═══════════════════════════════════════════════════════════════");
  console.log("   ✨ All addresses match official ERC-8004 pattern! ✨         ");
  console.log("═══════════════════════════════════════════════════════════════");
}

main().catch((error) => {
  console.error("\n❌ Error:", error);
  process.exit(1);
});

