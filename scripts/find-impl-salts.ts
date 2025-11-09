import hre from "hardhat";
import { getCreate2Address, Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Target implementation addresses from our vanity search
 */
const TARGET_ADDRESSES = {
  identityRegistry: "0x610178da211fef7d417bc0e6fed39f05609ad788",
  reputationRegistry: "0xb7f8bc63bbcad18155201308c8f3540b07f84f5e",
  validationRegistry: "0xa51c1fc2f0d1a1b8494ed1fe312d7c3a78ed91c0",
} as const;

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

function findSaltForAddress(
  bytecode: Hex,
  targetAddress: string,
  contractName: string
): { salt: Hex; address: string } {
  const normalizedTarget = targetAddress.toLowerCase();
  let salt = 0n;

  console.log(`Finding salt for ${contractName} to match ${targetAddress}...`);

  const startTime = Date.now();

  while (true) {
    const saltHex = `0x${salt.toString(16).padStart(64, "0")}` as Hex;
    const address = computeCreate2Address(SAFE_SINGLETON_FACTORY, bytecode, saltHex);

    if (address.toLowerCase() === normalizedTarget) {
      const elapsed = (Date.now() - startTime) / 1000;
      console.log(`✅ Found salt for ${contractName} in ${elapsed.toFixed(2)}s`);
      console.log(`   Salt: ${saltHex}`);
      console.log(`   Address: ${address}`);
      return { salt: saltHex, address };
    }

    salt++;

    if (salt > 100_000_000n) {
      throw new Error(`Could not find salt for ${contractName} after 100M iterations`);
    }
  }
}

async function main() {
  console.log("Finding Salts for Implementation Contract Addresses");
  console.log("===================================================");
  console.log("");

  // Get contract bytecodes
  const identityArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  const identityBytecode = identityArtifact.bytecode as Hex;
  const reputationBytecode = reputationArtifact.bytecode as Hex;
  const validationBytecode = validationArtifact.bytecode as Hex;

  // Find salts
  const identityResult = findSaltForAddress(
    identityBytecode,
    TARGET_ADDRESSES.identityRegistry,
    "IdentityRegistry"
  );
  console.log("");

  const reputationResult = findSaltForAddress(
    reputationBytecode,
    TARGET_ADDRESSES.reputationRegistry,
    "ReputationRegistry"
  );
  console.log("");

  const validationResult = findSaltForAddress(
    validationBytecode,
    TARGET_ADDRESSES.validationRegistry,
    "ValidationRegistry"
  );
  console.log("");

  console.log("=".repeat(80));
  console.log("Implementation Salts Found!");
  console.log("=".repeat(80));
  console.log("");
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

  return {
    identityRegistry: identityResult,
    reputationRegistry: reputationResult,
    validationRegistry: validationResult,
  };
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
