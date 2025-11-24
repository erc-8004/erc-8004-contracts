import hre from "hardhat";
import { Hex } from "viem";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Salt for MinimalUUPS deployment (arbitrary, using 0x00...01 for simplicity)
 */
const MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;

/**
 * Expected MinimalUUPS address (deterministic across all networks)
 * This MUST match or deployment will fail
 */
const EXPECTED_MINIMAL_UUPS_ADDRESS = "0xF8AD590D320f6b5b43A11033cFdFC3eB588Fbf4a" as const;

/**
 * Deploy MinimalUUPS via CREATE2 to get a deterministic address
 */
async function main() {
  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log("Deploying MinimalUUPS via CREATE2");
  console.log("=================================");
  console.log("Deployer address:", deployer.account.address);
  console.log("");

  // Get MinimalUUPS bytecode
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");
  const bytecode = minimalUUPSArtifact.bytecode as Hex;

  console.log("MinimalUUPS bytecode length:", bytecode.length);
  console.log("");

  // Compute the expected address first
  const { getCreate2Address, keccak256 } = await import("viem");
  const minimalUUPSAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: MINIMAL_UUPS_SALT,
    bytecodeHash: keccak256(bytecode),
  });

  // Check if already deployed
  const existingCode = await publicClient.getBytecode({
    address: minimalUUPSAddress,
  });

  if (existingCode !== undefined && existingCode !== "0x") {
    console.log("MinimalUUPS already deployed at:", minimalUUPSAddress);
    console.log("   Bytecode length:", existingCode.length);
    console.log("");
  } else {
    // Deploy via CREATE2
    console.log("Deploying MinimalUUPS via CREATE2 factory...");
    const deployData = (MINIMAL_UUPS_SALT + bytecode.slice(2)) as Hex;

    const txHash = await deployer.sendTransaction({
      to: SAFE_SINGLETON_FACTORY,
      data: deployData,
    });

    await publicClient.waitForTransactionReceipt({ hash: txHash });

    console.log("✅ MinimalUUPS deployed at:", minimalUUPSAddress);
    console.log("");
  }

  // Verify address matches expected
  if (minimalUUPSAddress.toLowerCase() !== EXPECTED_MINIMAL_UUPS_ADDRESS.toLowerCase()) {
    console.error("❌ ERROR: MinimalUUPS address mismatch!");
    console.error(`   Expected: ${EXPECTED_MINIMAL_UUPS_ADDRESS}`);
    console.error(`   Got:      ${minimalUUPSAddress}`);
    console.error("");
    console.error("This means the MinimalUUPS bytecode has changed.");
    console.error("You need to:");
    console.error("1. Update EXPECTED_MINIMAL_UUPS_ADDRESS in this script");
    console.error("2. Update PLACEHOLDER_ADDRESS in find-vanity-salts.ts");
    console.error("3. Re-run find-vanity-salts-parallel.ts to get new salts");
    console.error("4. Update MINIMAL_UUPS_ADDRESS and salts in deploy-vanity.ts");
    throw new Error("MinimalUUPS address mismatch");
  }

  console.log("✅ Address verification: PASSED");
  console.log(`   MinimalUUPS address matches expected: ${EXPECTED_MINIMAL_UUPS_ADDRESS}`);
  console.log("");

  return minimalUUPSAddress;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
