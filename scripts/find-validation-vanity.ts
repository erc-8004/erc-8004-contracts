import hre from "hardhat";
import { getCreate2Address, keccak256, encodeAbiParameters, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

// Known values from previous run
const IDENTITY_IMPL = "0x610178da211fef7d417bc0e6fed39f05609ad788";
const VALIDATION_IMPL = "0xa51c1fc2f0d1a1b8494ed1fe312d7c3a78ed91c0";
const IDENTITY_PROXY = "0x8004A38aA4dE46632aa597FFCe73F26c03850737";

/**
 * Computes CREATE2 address for a given salt
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
 * Checks if address has uppercase C after 0x8004
 */
function hasUppercaseC(address: string): boolean {
  // Address format: 0x8004C...
  // We need to check the 5th character (index 6 after "0x8004")
  if (address.length < 7) return false;
  const char = address[6];
  return char === 'C';
}

/**
 * Finds a salt that generates an address with uppercase 0x8004C prefix
 */
function findVanitySalt(
  bytecode: Hex,
  startSalt: bigint = 0n
): { salt: Hex; address: string; iterations: number } {
  let salt = startSalt;
  let iterations = 0;

  console.log(`Searching for address with prefix: 0x8004C (uppercase C)`);
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

    // Check if address starts with 0x8004 and has uppercase C
    if (address.toLowerCase().startsWith("0x8004c") && hasUppercaseC(address)) {
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

    // Safety limit
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
  console.log("Finding Vanity Address for ValidationRegistry (0x8004C with uppercase C)");
  console.log("=".repeat(80));
  console.log("");

  // Prepare ValidationRegistry initialization calldata
  const validationInitCalldata = encodeAbiParameters(
    [{ name: "identityRegistry", type: "address" }],
    [IDENTITY_PROXY as `0x${string}`]
  );
  const validationInitData = ("0xc4d66de8" + validationInitCalldata.slice(2)) as Hex;

  const validationProxyBytecode = await getProxyBytecode(
    VALIDATION_IMPL,
    validationInitData
  );

  // Start searching from salt 64839 (after the previous failed attempt)
  const validationResult = findVanitySalt(validationProxyBytecode, 64839n);

  console.log("");
  console.log("=".repeat(80));
  console.log("ValidationRegistry Vanity Address Found!");
  console.log("=".repeat(80));
  console.log("Salt:    ", validationResult.salt);
  console.log("Address: ", validationResult.address);
  console.log("");

  return validationResult;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
