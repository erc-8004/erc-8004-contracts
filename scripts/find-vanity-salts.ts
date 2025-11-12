import hre from "hardhat";
import { getCreate2Address, encodeAbiParameters, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * MinimalUUPS address deployed via CREATE2 (deterministic)
 */
const PLACEHOLDER_ADDRESS = "0xB0324bB5D23481009EfdDbD1fA8B5544FBeae60d" as const;

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
 * Checks if address has uppercase letter after 0x8004
 */
function hasUppercase(address: string, targetChar: string): boolean {
  if (address.length < 7) return false;
  const char = address[6];
  return char === targetChar;
}

/**
 * Finds a salt that generates an address with the desired prefix
 */
function findVanitySalt(
  prefix: string,
  bytecode: Hex,
  targetChar: string,
  startSalt: bigint = 0n
): { salt: Hex; address: string; iterations: number } {
  const normalizedPrefix = prefix.toLowerCase();
  let salt = startSalt;
  let iterations = 0;

  console.log(`Searching for address with prefix: ${prefix} (uppercase ${targetChar})`);
  console.log(`Starting from salt: ${salt}`);

  const startTime = Date.now();
  let lastLogTime = startTime;

  while (true) {
    iterations++;

    const saltHex = `0x${salt.toString(16).padStart(64, "0")}` as Hex;
    const address = computeCreate2Address(
      SAFE_SINGLETON_FACTORY,
      bytecode,
      saltHex
    );

    // Check if address starts with desired prefix and has uppercase letter
    if (address.toLowerCase().startsWith(normalizedPrefix) && hasUppercase(address, targetChar)) {
      const elapsed = (Date.now() - startTime) / 1000;
      console.log(`✅ Found matching address after ${iterations.toLocaleString()} iterations in ${elapsed.toFixed(2)}s`);
      console.log(`   Salt: ${saltHex}`);
      console.log(`   Address: ${address}`);
      return { salt: saltHex, address, iterations };
    }

    const now = Date.now();
    if (now - lastLogTime > 10000) {
      const elapsed = (now - startTime) / 1000;
      const rate = iterations / elapsed;
      console.log(`   Checked ${iterations.toLocaleString()} salts (${rate.toFixed(0)} per second)...`);
      lastLogTime = now;
    }

    salt++;

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
  const proxyArtifact = await hre.artifacts.readArtifact("ERC1967Proxy");

  const constructorArgs = encodeAbiParameters(
    [
      { name: "implementation", type: "address" },
      { name: "data", type: "bytes" }
    ],
    [implementationAddress as `0x${string}`, initCalldata]
  );

  const fullBytecode = (proxyArtifact.bytecode + constructorArgs.slice(2)) as Hex;
  return fullBytecode;
}

async function main() {
  console.log("Finding Vanity Addresses for ERC-8004 Proxies (pointing to 0x...8004)");
  console.log("=======================================================================");
  console.log("");

  // All proxies initially point to placeholder address with empty init data
  const emptyInitData = "0x" as Hex;

  // Get proxy bytecode pointing to placeholder address
  const proxyBytecode = await getProxyBytecode(PLACEHOLDER_ADDRESS, emptyInitData);

  console.log(`Finding vanity salts for proxies pointing to ${PLACEHOLDER_ADDRESS}`);
  console.log("");

  // Find salt for IdentityRegistry proxy (0x8004A)
  console.log("1. Finding salt for IdentityRegistry (0x8004A)...");
  const identityResult = findVanitySalt("0x8004a", proxyBytecode, "A");
  console.log("");

  // Find salt for ReputationRegistry proxy (0x8004B)
  console.log("2. Finding salt for ReputationRegistry (0x8004B)...");
  const reputationResult = findVanitySalt("0x8004b", proxyBytecode, "B");
  console.log("");

  // Find salt for ValidationRegistry proxy (0x8004C)
  console.log("3. Finding salt for ValidationRegistry (0x8004C)...");
  const validationResult = findVanitySalt("0x8004c", proxyBytecode, "C");
  console.log("");

  // Summary
  console.log("=".repeat(80));
  console.log("Vanity Proxy Salts Found!");
  console.log("=".repeat(80));
  console.log("");
  console.log("All proxies initially point to:", PLACEHOLDER_ADDRESS);
  console.log("");
  console.log("IdentityRegistry Proxy:");
  console.log("  Salt:    ", identityResult.salt);
  console.log("  Address: ", identityResult.address);
  console.log("");
  console.log("ReputationRegistry Proxy:");
  console.log("  Salt:    ", reputationResult.salt);
  console.log("  Address: ", reputationResult.address);
  console.log("");
  console.log("ValidationRegistry Proxy:");
  console.log("  Salt:    ", validationResult.salt);
  console.log("  Address: ", validationResult.address);
  console.log("");
  console.log("=".repeat(80));
  console.log("Next steps:");
  console.log("1. Deploy proxies with these salts (pointing to 0x...8004)");
  console.log("2. Deploy implementation contracts");
  console.log("3. Call upgradeToAndCall() on each proxy to point to implementations");
  console.log("");

  return {
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
