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

  // Deploy via CREATE2
  console.log("Deploying MinimalUUPS via CREATE2 factory...");
  const deployData = (MINIMAL_UUPS_SALT + bytecode.slice(2)) as Hex;

  const txHash = await deployer.sendTransaction({
    to: SAFE_SINGLETON_FACTORY,
    data: deployData,
  });

  await publicClient.waitForTransactionReceipt({ hash: txHash });

  // Compute the expected address
  const { getCreate2Address } = await import("viem");
  const minimalUUPSAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: MINIMAL_UUPS_SALT,
    bytecode: bytecode,
  });

  console.log("✅ MinimalUUPS deployed at:", minimalUUPSAddress);
  console.log("");
  console.log("Use this address in find-vanity-zero.ts:");
  console.log(`const PLACEHOLDER_ADDRESS = "${minimalUUPSAddress}" as const;`);
  console.log("");

  return minimalUUPSAddress;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
