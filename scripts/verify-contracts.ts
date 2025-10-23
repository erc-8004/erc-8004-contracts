/**
 * Verify deployed contracts on 0G explorer
 * 
 * Usage: npx hardhat verify --network zeroG <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
 */

const contracts = {
  // Implementation contracts (verify these first)
  implementations: {
    identity: {
      address: "0x0c342a7342237976236819b3160f9d7ea8c23ac6",
      contract: "contracts/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable",
      constructorArgs: []
    },
    reputation: {
      address: "0x363a785f1c83d375f275fb121ee8087b7e31f5c4",
      contract: "contracts/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable",
      constructorArgs: []
    },
    validation: {
      address: "0x6251598b4fe45dcadfd2e6dc42b007498073af4a",
      contract: "contracts/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable",
      constructorArgs: []
    }
  },
  
  // Proxy contracts (canonical 0x8004 addresses)
  proxies: {
    identity: {
      address: "0x80043ed9cf33a3472768dcd53175bb44e03a1e4a",
      contract: "contracts/ERC1967Proxy.sol:ERC1967Proxy",
      constructorArgs: [
        "0x0c342a7342237976236819b3160f9d7ea8c23ac6", // implementation
        "0x8129fc1c" // initialize() selector
      ]
    },
    reputation: {
      address: "0x80045d7b72c47bf5ff73737b780cb1a5ba8ee202",
      contract: "contracts/ERC1967Proxy.sol:ERC1967Proxy",
      constructorArgs: [
        "0x363a785f1c83d375f275fb121ee8087b7e31f5c4", // implementation
        "0xc4d66de880043ed9cf33a3472768dcd53175bb44e03a1e4a000000000000000000000000" // initialize(identity) calldata
      ]
    },
    validation: {
      address: "0x80041728e0aadf1d1427f9be18d52b7f3afefafb",
      contract: "contracts/ERC1967Proxy.sol:ERC1967Proxy",
      constructorArgs: [
        "0x6251598b4fe45dcadfd2e6dc42b007498073af4a", // implementation
        "0xc4d66de880043ed9cf33a3472768dcd53175bb44e03a1e4a000000000000000000000000" // initialize(identity) calldata
      ]
    }
  },
  
  // CREATE2 Factory
  factory: {
    address: "0xbb5be4b3cc4b81dc52fb7b0c2b53bd7de19a5f84",
    contract: "contracts/Create2Factory.sol:Create2Factory",
    constructorArgs: []
  }
};

console.log("=== Contract Verification Guide ===\n");
console.log("Run these commands to verify on 0G explorer:\n");

console.log("# 1. Verify Implementation Contracts");
console.log(`npx hardhat verify --network zeroG ${contracts.implementations.identity.address}`);
console.log(`npx hardhat verify --network zeroG ${contracts.implementations.reputation.address}`);
console.log(`npx hardhat verify --network zeroG ${contracts.implementations.validation.address}`);

console.log("\n# 2. Verify CREATE2 Factory");
console.log(`npx hardhat verify --network zeroG ${contracts.factory.address}`);

console.log("\n# 3. Verify Proxy Contracts (may need manual verification)");
console.log(`npx hardhat verify --network zeroG ${contracts.proxies.identity.address} "${contracts.proxies.identity.constructorArgs[0]}" "${contracts.proxies.identity.constructorArgs[1]}"`);

console.log("\n=== Contract Addresses ===\n");
console.log("Canonical Proxies (0x8004...):");
console.log(`  Identity:    ${contracts.proxies.identity.address}`);
console.log(`  Reputation:  ${contracts.proxies.reputation.address}`);
console.log(`  Validation:  ${contracts.proxies.validation.address}`);

console.log("\nImplementations:");
console.log(`  Identity:    ${contracts.implementations.identity.address}`);
console.log(`  Reputation:  ${contracts.implementations.reputation.address}`);
console.log(`  Validation:  ${contracts.implementations.validation.address}`);

console.log("\nCREATE2 Factory:");
console.log(`  Factory:     ${contracts.factory.address}`);

console.log("\n=== Explorer Links ===");
console.log(`Identity:    https://chainscan-galileo.0g.ai/address/${contracts.proxies.identity.address}`);
console.log(`Reputation:  https://chainscan-galileo.0g.ai/address/${contracts.proxies.reputation.address}`);
console.log(`Validation:  https://chainscan-galileo.0g.ai/address/${contracts.proxies.validation.address}`);

