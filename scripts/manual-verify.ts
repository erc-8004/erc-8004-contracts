import { readFileSync } from 'fs';
import { join } from 'path';

// Contracts to verify
const contracts = [
  {
    name: "IdentityRegistryUpgradeable",
    address: "0x0c342a7342237976236819b3160f9d7ea8c23ac6",
    path: "contracts/IdentityRegistryUpgradeable.sol"
  },
  {
    name: "ReputationRegistryUpgradeable",
    address: "0x363a785f1c83d375f275fb121ee8087b7e31f5c4",
    path: "contracts/ReputationRegistryUpgradeable.sol"
  },
  {
    name: "ValidationRegistryUpgradeable",
    address: "0x6251598b4fe45dcadfd2e6dc42b007498073af4a",
    path: "contracts/ValidationRegistryUpgradeable.sol"
  },
  {
    name: "Create2Factory",
    address: "0xbb5be4b3cc4b81dc52fb7b0c2b53bd7de19a5f84",
    path: "contracts/Create2Factory.sol"
  }
];

console.log("=== Manual Verification Instructions ===\n");
console.log("Since the hardhat-verify plugin doesn't recognize 0G as a custom chain,");
console.log("you'll need to verify manually on the 0G explorer.\n");
console.log("Explorer: https://chainscan-galileo.0g.ai\n");

for (const contract of contracts) {
  console.log(`\n--- ${contract.name} ---`);
  console.log(`Address: ${contract.address}`);
  console.log(`File: ${contract.path}`);
  console.log(`Compiler: solc 0.8.28`);
  console.log(`Optimization: enabled (200 runs)`);
  console.log(`EVM Version: cancun`);
  console.log(`Link: https://chainscan-galileo.0g.ai/address/${contract.address}\n`);
  console.log("Steps:");
  console.log("1. Visit the address link above");
  console.log("2. Click 'Verify & Publish' or 'Contract' tab");
  console.log("3. Select 'Solidity (Single file)' or 'Solidity (Standard-JSON-Input)'");
  console.log("4. Enter compiler version: v0.8.28");
  console.log("5. Set optimization: Yes, 200 runs");
  console.log("6. Set EVM version: cancun");
  console.log("7. Paste the flattened contract source");
  console.log(`8. Submit for verification\n`);
}

console.log("\n=== To flatten contracts for verification ===");
console.log("Run: npx hardhat flatten <CONTRACT_PATH> > flattened.sol\n");
console.log("Example:");
for (const contract of contracts.slice(0, 1)) {
  console.log(`npx hardhat flatten ${contract.path} > ${contract.name}_flattened.sol`);
}

