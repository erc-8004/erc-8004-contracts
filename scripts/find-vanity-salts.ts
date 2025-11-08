import hre from "hardhat";
import { getCreate2Address, keccak256, encodeAbiParameters, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Computes CREATE2 address for a given salt
 * @param factoryAddress - Address of the CREATE2 factory
 * @param bytecode - Contract bytecode to deploy
 * @param salt - Salt value for CREATE2
 * @returns The computed CREATE2 address
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
 * Finds a salt that generates an address with the desired prefix
 * @param prefix - Desired address prefix (e.g., "0x8004A")
 * @param bytecode - Contract bytecode to deploy
 * @param startSalt - Starting salt value (for resuming search)
 * @returns Object containing the salt and resulting address
 */
function findVanitySalt(
  prefix: string,
  bytecode: Hex,
  startSalt: bigint = 0n
): { salt: Hex; address: string; iterations: number } {
  const normalizedPrefix = prefix.toLowerCase();
  let salt = startSalt;
  let iterations = 0;

  console.log(`Searching for address with prefix: ${prefix}`);
  console.log(`Starting from salt: ${salt}`);

  const startTime = Date.now();
  let lastLogTime = startTime;

  while (true) {
    iterations++;

    // Convert salt to 32-byte hex string
    const saltHex = `0x${salt.toString(16).padStart(64, "0")}` as Hex;

    // Compute CREATE2 address
    const address = computeCreate2Address(
      SAFE_SINGLETON_FACTORY,
      bytecode,
      saltHex
    );

    // Check if address starts with desired prefix
    if (address.toLowerCase().startsWith(normalizedPrefix)) {
      const elapsed = (Date.now() - startTime) / 1000;
      console.log(`✅ Found matching address after ${iterations.toLocaleString()} iterations in ${elapsed.toFixed(2)}s`);
      console.log(`   Salt: ${saltHex}`);
      console.log(`   Address: ${address}`);
      return { salt: saltHex, address, iterations };
    }

    // Log progress every 10 seconds
    const now = Date.now();
    if (now - lastLogTime > 10000) {
      const elapsed = (now - startTime) / 1000;
      const rate = iterations / elapsed;
      console.log(`   Checked ${iterations.toLocaleString()} salts (${rate.toFixed(0)} per second)...`);
      lastLogTime = now;
    }

    salt++;

    // Safety limit to prevent infinite loops
    if (iterations > 100_000_000) {
      throw new Error("Search limit reached. Try a shorter or easier prefix.");
    }
  }
}

/**
 * Gets the deployment bytecode for a proxy contract
 */
async function getProxyBytecode(
  implementationAddress: string,
  initCalldata: Hex
): Promise<Hex> {
  const { viem } = await hre.network.connect();

  // Get the ERC1967Proxy artifact
  const proxyArtifact = await hre.artifacts.readArtifact("ERC1967Proxy");

  // Encode constructor arguments
  const constructorArgs = encodeAbiParameters(
    [
      { name: "implementation", type: "address" },
      { name: "data", type: "bytes" }
    ],
    [implementationAddress as `0x${string}`, initCalldata]
  );

  // Combine bytecode and constructor args
  const fullBytecode = (proxyArtifact.bytecode + constructorArgs.slice(2)) as Hex;

  return fullBytecode;
}

async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Finding Vanity Addresses for ERC-8004 Registries");
  console.log("================================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Step 1: Deploy implementations (needed to compute proxy bytecode)
  console.log("Step 1: Deploying implementation contracts...");

  const identityRegistryImpl = await viem.deployContract("IdentityRegistryUpgradeable");
  console.log("   IdentityRegistry implementation:", identityRegistryImpl.address);

  const reputationRegistryImpl = await viem.deployContract("ReputationRegistryUpgradeable");
  console.log("   ReputationRegistry implementation:", reputationRegistryImpl.address);

  const validationRegistryImpl = await viem.deployContract("ValidationRegistryUpgradeable");
  console.log("   ValidationRegistry implementation:", validationRegistryImpl.address);
  console.log("");

  // Step 2: Prepare initialization calldata
  console.log("Step 2: Preparing initialization calldata...");

  // IdentityRegistry: initialize() with no parameters
  const identityInitCalldata = "0x8129fc1c" as Hex;

  // For ReputationRegistry and ValidationRegistry, we need the identity proxy address
  // But we don't have it yet! We need to find its salt first, then compute its address
  // So we'll find the identity salt first, compute its address, then use that for the others

  console.log("");

  // Step 3: Find salt for IdentityRegistry proxy (0x8004A)
  console.log("Step 3: Finding salt for IdentityRegistry (prefix: 0x8004A)...");
  const identityProxyBytecode = await getProxyBytecode(
    identityRegistryImpl.address,
    identityInitCalldata
  );

  const identityResult = findVanitySalt("0x8004A", identityProxyBytecode);
  console.log("");

  // Compute the identity proxy address using the found salt
  const identityProxyAddress = identityResult.address;

  // Step 4: Find salt for ReputationRegistry proxy (0x8004B)
  console.log("Step 4: Finding salt for ReputationRegistry (prefix: 0x8004B)...");

  // Now we can create the proper init calldata with the identity proxy address
  const reputationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxyAddress as `0x${string}`]
  );
  const reputationInitData = ("0xc4d66de8" + reputationInitCalldata.slice(2)) as Hex;

  const reputationProxyBytecode = await getProxyBytecode(
    reputationRegistryImpl.address,
    reputationInitData
  );

  const reputationResult = findVanitySalt("0x8004B", reputationProxyBytecode);
  console.log("");

  // Step 5: Find salt for ValidationRegistry proxy (0x8004C)
  console.log("Step 5: Finding salt for ValidationRegistry (prefix: 0x8004C)...");

  const validationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [identityProxyAddress as `0x${string}`]
  );
  const validationInitData = ("0xc4d66de8" + validationInitCalldata.slice(2)) as Hex;

  const validationProxyBytecode = await getProxyBytecode(
    validationRegistryImpl.address,
    validationInitData
  );

  const validationResult = findVanitySalt("0x8004C", validationProxyBytecode);
  console.log("");

  // Summary
  console.log("=".repeat(80));
  console.log("Vanity Address Configuration Found!");
  console.log("=".repeat(80));
  console.log("");
  console.log("Implementation Addresses:");
  console.log("-".repeat(80));
  console.log("IdentityRegistry:   ", identityRegistryImpl.address);
  console.log("ReputationRegistry: ", reputationRegistryImpl.address);
  console.log("ValidationRegistry: ", validationRegistryImpl.address);
  console.log("");
  console.log("Vanity Proxy Salts & Addresses:");
  console.log("-".repeat(80));
  console.log("IdentityRegistry:");
  console.log("  Salt:    ", identityResult.salt);
  console.log("  Address: ", identityResult.address);
  console.log("");
  console.log("ReputationRegistry:");
  console.log("  Salt:    ", reputationResult.salt);
  console.log("  Address: ", reputationResult.address);
  console.log("");
  console.log("ValidationRegistry:");
  console.log("  Salt:    ", validationResult.salt);
  console.log("  Address: ", validationResult.address);
  console.log("");
  console.log("=".repeat(80));
  console.log("");
  console.log("Copy these values to deploy-upgradeable-vanity.ts");
  console.log("");

  return {
    implementations: {
      identity: identityRegistryImpl.address,
      reputation: reputationRegistryImpl.address,
      validation: validationRegistryImpl.address
    },
    salts: {
      identity: identityResult.salt,
      reputation: reputationResult.salt,
      validation: validationResult.salt
    },
    addresses: {
      identity: identityResult.address,
      reputation: reputationResult.address,
      validation: validationResult.address
    }
  };
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
