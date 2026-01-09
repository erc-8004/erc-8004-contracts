import hre from "hardhat";
import { getCreate2Address, encodeFunctionData, keccak256, Hex, encodeAbiParameters } from "viem";
import { Worker } from "worker_threads";
import * as os from "os";

/**
 * SAFE Singleton CREATE2 Factory address
 */
const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Salt for MinimalUUPS deployment (single instance for all registries)
 */
const MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;

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

/**
 * Search for vanity address in parallel using worker threads
 */
function findVanitySaltParallel(
  prefix: string,
  bytecode: Hex,
  targetChar: string,
  numWorkers: number = os.cpus().length
): Promise<{ salt: Hex; address: string; iterations: number }> {
  return new Promise((resolve, reject) => {
    console.log(`Searching for address with prefix: ${prefix} (uppercase ${targetChar})`);
    console.log(`Using ${numWorkers} worker threads`);

    const workers: Worker[] = [];
    let found = false;
    const startTime = Date.now();

    // Create worker code as a string
    const workerCode = `
      const { parentPort, workerData } = require('worker_threads');
      const { getCreate2Address, keccak256 } = require('viem');

      const { startSalt, factoryAddress, bytecode, prefix, targetChar } = workerData;

      function hasUppercase(address, targetChar) {
        if (address.length < 7) return false;
        const char = address[6];
        return char === targetChar;
      }

      let salt = BigInt(startSalt);
      let iterations = 0;
      const normalizedPrefix = prefix.toLowerCase();
      let found = false;

      while (!found) {
        iterations++;

        const saltHex = '0x' + salt.toString(16).padStart(64, '0');
        const address = getCreate2Address({
          from: factoryAddress,
          salt: saltHex,
          bytecodeHash: keccak256(bytecode),
        });

        if (address.toLowerCase().startsWith(normalizedPrefix) && hasUppercase(address, targetChar)) {
          parentPort.postMessage({
            type: 'found',
            salt: saltHex,
            address,
            iterations
          });
          found = true;
          break;
        }

        // Check every 10000 iterations if we should stop
        if (iterations % 10000 === 0) {
          parentPort.postMessage({
            type: 'progress',
            iterations
          });
        }

        salt += BigInt(${numWorkers});
      }
    `;

    // Create workers
    for (let i = 0; i < numWorkers; i++) {
      const worker = new Worker(workerCode, {
        eval: true,
        workerData: {
          startSalt: i,
          factoryAddress: SAFE_SINGLETON_FACTORY,
          bytecode,
          prefix,
          targetChar
        }
      });

      worker.on('message', (msg) => {
        if (msg.type === 'found' && !found) {
          found = true;
          const elapsed = (Date.now() - startTime) / 1000;
          console.log(`✅ Found matching address after ${msg.iterations.toLocaleString()} iterations in ${elapsed.toFixed(2)}s`);
          console.log(`   Salt: ${msg.salt}`);
          console.log(`   Address: ${msg.address}`);

          // Terminate all workers
          workers.forEach(w => w.terminate());

          resolve({
            salt: msg.salt as Hex,
            address: msg.address,
            iterations: msg.iterations
          });
        }
      });

      worker.on('error', reject);
      worker.on('exit', (code) => {
        if (code !== 0 && !found) {
          reject(new Error(`Worker stopped with exit code ${code}`));
        }
      });

      workers.push(worker);
    }
  });
}

async function main() {
  console.log("Finding Vanity Addresses for ERC-8004 Proxies (PARALLEL)");
  console.log("=".repeat(70));
  console.log("");

  const numWorkers = os.cpus().length;
  console.log(`System has ${numWorkers} CPU cores`);
  console.log("");

  // Calculate MinimalUUPS address (single instance)
  console.log("Step 0: Calculating MinimalUUPS address...");
  const minimalUUPSArtifact = await hre.artifacts.readArtifact("MinimalUUPS");
  const minimalUUPSBytecode = minimalUUPSArtifact.bytecode as Hex;

  const minimalUUPSAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: MINIMAL_UUPS_SALT,
    bytecodeHash: keccak256(minimalUUPSBytecode),
  });

  console.log(`✅ MinimalUUPS: ${minimalUUPSAddress}`);
  console.log("");

  // Find salt for IdentityRegistry proxy (0x8004A)
  // Initialize with zero address
  console.log("Step 1: Finding salt for IdentityRegistry (0x8004A)...");
  console.log("        Initialize with: 0x0000000000000000000000000000000000000000");
  const identityInitData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "initialize",
    args: ["0x0000000000000000000000000000000000000000" as `0x${string}`]
  });
  const identityProxyBytecode = await getProxyBytecode(minimalUUPSAddress, identityInitData);
  const identityResult = await findVanitySaltParallel("0x8004a", identityProxyBytecode, "A", numWorkers);
  console.log("");

  // Calculate IdentityRegistry proxy address
  console.log("Step 2: Calculating IdentityRegistry proxy address...");
  const identityProxyAddress = getCreate2Address({
    from: SAFE_SINGLETON_FACTORY,
    salt: identityResult.salt,
    bytecodeHash: keccak256(identityProxyBytecode),
  });
  console.log(`✅ IdentityRegistry proxy will be at: ${identityProxyAddress}`);
  console.log("");

  // Find salt for ReputationRegistry proxy (0x8004B)
  // Initialize with IdentityRegistry address
  console.log("Step 3: Finding salt for ReputationRegistry (0x8004B)...");
  console.log(`        Initialize with: ${identityProxyAddress}`);
  const reputationInitData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "initialize",
    args: [identityProxyAddress]
  });
  const reputationProxyBytecode = await getProxyBytecode(minimalUUPSAddress, reputationInitData);
  const reputationResult = await findVanitySaltParallel("0x8004b", reputationProxyBytecode, "B", numWorkers);
  console.log("");

  // Find salt for ValidationRegistry proxy (0x8004C)
  // Initialize with IdentityRegistry address
  console.log("Step 4: Finding salt for ValidationRegistry (0x8004C)...");
  console.log(`        Initialize with: ${identityProxyAddress}`);
  const validationInitData = encodeFunctionData({
    abi: minimalUUPSArtifact.abi,
    functionName: "initialize",
    args: [identityProxyAddress]
  });
  const validationProxyBytecode = await getProxyBytecode(minimalUUPSAddress, validationInitData);
  const validationResult = await findVanitySaltParallel("0x8004c", validationProxyBytecode, "C", numWorkers);
  console.log("");

  // Summary
  console.log("=".repeat(80));
  console.log("Vanity Proxy Salts Found!");
  console.log("=".repeat(80));
  console.log("");
  console.log("MinimalUUPS Address:", minimalUUPSAddress);
  console.log("");
  console.log("IdentityRegistry Proxy:");
  console.log("  Salt:    ", identityResult.salt);
  console.log("  Address: ", identityResult.address);
  console.log("  Init:     MinimalUUPS.initialize(0x0000000000000000000000000000000000000000)");
  console.log("");
  console.log("ReputationRegistry Proxy:");
  console.log("  Salt:    ", reputationResult.salt);
  console.log("  Address: ", reputationResult.address);
  console.log(`  Init:     MinimalUUPS.initialize(${identityProxyAddress})`);
  console.log("");
  console.log("ValidationRegistry Proxy:");
  console.log("  Salt:    ", validationResult.salt);
  console.log("  Address: ", validationResult.address);
  console.log(`  Init:     MinimalUUPS.initialize(${identityProxyAddress})`);
  console.log("");
  console.log("=".repeat(80));
  console.log("Next steps:");
  console.log("1. Update VANITY_SALTS in scripts/deploy-vanity.ts");
  console.log("2. Update EXPECTED_ADDRESSES in scripts/deploy-vanity.ts");
  console.log("3. Update scripts/verify-vanity.ts with new addresses");
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
