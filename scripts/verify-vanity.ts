import hre from "hardhat";

/**
 * Expected vanity proxy addresses (deterministic across all networks)
 */
const EXPECTED_ADDRESSES = {
  identityRegistry: "0x8004A818BFB912233c491871b3d84c89A494BD9e",
  reputationRegistry: "0x8004B663056A597Dffe9eCcC1965A193B7388713",
  validationRegistry: "0x8004Cb1BF31DAf7788923b405b754f57acEB4272",
} as const;

/**
 * Expected owner address (from MinimalUUPS.sol)
 */
const EXPECTED_OWNER = "0x547289319C3e6aedB179C0b8e8aF0B5ACd062603" as const;

/**
 * Verify vanity deployment
 * This script checks that all contracts are properly deployed and configured
 */
async function main() {
  const { viem } = await hre.network.connect() as any;
  const publicClient = await viem.getPublicClient();

  console.log("Verifying ERC-8004 Vanity Deployment");
  console.log("=====================================");
  console.log("");

  // Load ABIs once
  const identityArtifact = await hre.artifacts.readArtifact("IdentityRegistryUpgradeable");
  const reputationArtifact = await hre.artifacts.readArtifact("ReputationRegistryUpgradeable");
  const validationArtifact = await hre.artifacts.readArtifact("ValidationRegistryUpgradeable");

  let allChecksPassed = true;

  // Check 1: Verify proxy addresses have code
  console.log("1. Checking proxy addresses have code...");
  for (const [name, address] of Object.entries(EXPECTED_ADDRESSES)) {
    const code = await publicClient.getBytecode({ address: address as `0x${string}` });
    if (!code || code === "0x") {
      console.log(`   ❌ ${name}: No code at ${address}`);
      allChecksPassed = false;
    } else {
      console.log(`   ✅ ${name}: ${address}`);
    }
  }
  console.log("");

  // Check 2: Connect to contracts and verify versions
  console.log("2. Checking contract versions...");
  try {
    const identityVersion = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.identityRegistry as `0x${string}`,
      abi: identityArtifact.abi,
      functionName: "getVersion",
      args: [],
    });
    console.log(`   ✅ IdentityRegistry version: ${identityVersion}`);

    const reputationVersion = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`,
      abi: reputationArtifact.abi,
      functionName: "getVersion",
      args: [],
    });
    console.log(`   ✅ ReputationRegistry version: ${reputationVersion}`);

    const validationVersion = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.validationRegistry as `0x${string}`,
      abi: validationArtifact.abi,
      functionName: "getVersion",
      args: [],
    });
    console.log(`   ✅ ValidationRegistry version: ${validationVersion}`);
  } catch (error) {
    console.log(`   ❌ Error reading versions: ${error}`);
    allChecksPassed = false;
  }
  console.log("");

  // Check 3: Verify ownership
  console.log("3. Checking ownership...");
  try {
    const identityOwner = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.identityRegistry as `0x${string}`,
      abi: identityArtifact.abi,
      functionName: "owner",
      args: [],
    }) as `0x${string}`;
    if (identityOwner.toLowerCase() === EXPECTED_OWNER.toLowerCase()) {
      console.log(`   ✅ IdentityRegistry owner: ${identityOwner}`);
    } else {
      console.log(`   ❌ IdentityRegistry owner mismatch: expected ${EXPECTED_OWNER}, got ${identityOwner}`);
      allChecksPassed = false;
    }

    const reputationOwner = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`,
      abi: reputationArtifact.abi,
      functionName: "owner",
      args: [],
    }) as `0x${string}`;
    if (reputationOwner.toLowerCase() === EXPECTED_OWNER.toLowerCase()) {
      console.log(`   ✅ ReputationRegistry owner: ${reputationOwner}`);
    } else {
      console.log(`   ❌ ReputationRegistry owner mismatch: expected ${EXPECTED_OWNER}, got ${reputationOwner}`);
      allChecksPassed = false;
    }

    const validationOwner = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.validationRegistry as `0x${string}`,
      abi: validationArtifact.abi,
      functionName: "owner",
      args: [],
    }) as `0x${string}`;
    if (validationOwner.toLowerCase() === EXPECTED_OWNER.toLowerCase()) {
      console.log(`   ✅ ValidationRegistry owner: ${validationOwner}`);
    } else {
      console.log(`   ❌ ValidationRegistry owner mismatch: expected ${EXPECTED_OWNER}, got ${validationOwner}`);
      allChecksPassed = false;
    }
  } catch (error) {
    console.log(`   ❌ Error checking ownership: ${error}`);
    allChecksPassed = false;
  }
  console.log("");

  // Check 4: Verify implementation addresses (via ERC1967 implementation slot)
  console.log("4. Checking implementation addresses...");
  const IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
  try {
    for (const [name, address] of Object.entries(EXPECTED_ADDRESSES)) {
      const implSlot = await publicClient.getStorageAt({
        address: address as `0x${string}`,
        slot: IMPLEMENTATION_SLOT as `0x${string}`,
      });
      if (implSlot && implSlot !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
        const implAddress = `0x${implSlot.slice(-40)}`;
        console.log(`   ✅ ${name} implementation: ${implAddress}`);
      } else {
        console.log(`   ❌ ${name}: No implementation found`);
        allChecksPassed = false;
      }
    }
  } catch (error) {
    console.log(`   ❌ Error reading implementations: ${error}`);
    allChecksPassed = false;
  }
  console.log("");

  // Check 5: Verify cross-registry references
  console.log("5. Checking identity registry references...");
  try {
    const reputationIdentityRef = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.reputationRegistry as `0x${string}`,
      abi: reputationArtifact.abi,
      functionName: "getIdentityRegistry",
      args: [],
    }) as `0x${string}`;
    if (reputationIdentityRef.toLowerCase() === EXPECTED_ADDRESSES.identityRegistry.toLowerCase()) {
      console.log(`   ✅ ReputationRegistry -> IdentityRegistry: ${reputationIdentityRef}`);
    } else {
      console.log(`   ❌ ReputationRegistry identity reference mismatch`);
      console.log(`      Expected: ${EXPECTED_ADDRESSES.identityRegistry}`);
      console.log(`      Got: ${reputationIdentityRef}`);
      allChecksPassed = false;
    }

    const validationIdentityRef = await publicClient.readContract({
      address: EXPECTED_ADDRESSES.validationRegistry as `0x${string}`,
      abi: validationArtifact.abi,
      functionName: "getIdentityRegistry",
      args: [],
    }) as `0x${string}`;
    if (validationIdentityRef.toLowerCase() === EXPECTED_ADDRESSES.identityRegistry.toLowerCase()) {
      console.log(`   ✅ ValidationRegistry -> IdentityRegistry: ${validationIdentityRef}`);
    } else {
      console.log(`   ❌ ValidationRegistry identity reference mismatch`);
      console.log(`      Expected: ${EXPECTED_ADDRESSES.identityRegistry}`);
      console.log(`      Got: ${validationIdentityRef}`);
      allChecksPassed = false;
    }
  } catch (error) {
    console.log(`   ❌ Error checking identity registry references: ${error}`);
    allChecksPassed = false;
  }
  console.log("");

  // Final summary
  console.log("=".repeat(80));
  if (allChecksPassed) {
    console.log("✅ ALL CHECKS PASSED");
    console.log("=".repeat(80));
    console.log("");
    console.log("Deployment verified successfully!");
    console.log("");
    console.log("Vanity Addresses:");
    console.log("  IdentityRegistry:    ", EXPECTED_ADDRESSES.identityRegistry);
    console.log("  ReputationRegistry:  ", EXPECTED_ADDRESSES.reputationRegistry);
    console.log("  ValidationRegistry:  ", EXPECTED_ADDRESSES.validationRegistry);
  } else {
    console.log("❌ SOME CHECKS FAILED");
    console.log("=".repeat(80));
    console.log("");
    console.log("Please review the errors above and fix the deployment.");
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
