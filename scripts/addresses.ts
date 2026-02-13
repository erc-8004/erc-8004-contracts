import { Hex } from "viem";

/**
 * Mainnet chainIds - must be explicitly listed
 */
export const MAINNET_CHAIN_IDS = [
  1,      // Ethereum
  8453,   // Base
  42161,  // Arbitrum One
  10,     // Optimism
  137,    // Polygon
  43114,  // Avalanche
  56,     // BSC
  143,    // Monad
  534352, // Scroll
  100,    // Gnosis
  42220,  // Celo
  167000, // Taiko
  59144,  // Linea
  4326,   // MegaETH
  196,    // XLayer
  2741,   // Abstract
  5000,   // Mantle
  1868,   // Soneium
  2345,   // GOAT Network
  1088,   // Metis
  295,    // Hedera
  1187947933, // SKALE Base
];

/**
 * Testnet chainIds - must be explicitly listed
 */
export const TESTNET_CHAIN_IDS = [
  31337,    // Hardhat local
  11155111, // Sepolia
  84532,    // Base Sepolia
  421614,   // Arbitrum Sepolia
  11155420, // Optimism Sepolia
  80002,    // Polygon Amoy
  43113,    // Avalanche Fuji
  97,       // BSC Testnet
  10143,    // Monad Testnet
  534351,   // Scroll Sepolia
  10200,    // Gnosis Chiado
  11142220, // Celo Sepolia
  167013,   // Taiko Hoodi
  6343,     // MegaETH Testnet
  59141,    // Linea Sepolia
  1952,      // XLayer Testnet
  11124,    // Abstract Sepolia
  5003,     // Mantle Sepolia
  1946,     // Soneium Minato
  48816,    // GOAT Testnet3
  59902,    // Metis Sepolia
  296,      // Hedera Testnet
  324705682, // SKALE Base Sepolia
];

/**
 * Testnet proxy addresses (MinimalUUPS v0.0.1)
 * Used for: Sepolia, Base Sepolia, Arbitrum Sepolia, etc.
 */
export const TESTNET_ADDRESSES = {
  identityRegistry: "0x8004A818BFB912233c491871b3d84c89A494BD9e",
  reputationRegistry: "0x8004B663056A597Dffe9eCcC1965A193B7388713",
  validationRegistry: "0x8004Cb1BF31DAf7788923b405b754f57acEB4272",
} as const;

/**
 * Mainnet proxy addresses (MinimalUUPSMainnet v1.0.0)
 * Used for: Ethereum, Base, Arbitrum One, etc.
 * TBD - need to mine vanity salts
 */
export const MAINNET_ADDRESSES = {
  identityRegistry: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  reputationRegistry: "0x8004BAa17C55a88189AE136b182e5fdA19dE9b63",
  validationRegistry: "0x8004Cc8439f36fd5F9F049D9fF86523Df6dAAB58",
} as const;

/**
 * Testnet vanity salts for CREATE2 proxy deployment
 */
export const TESTNET_VANITY_SALTS = {
  identityRegistry: "0x000000000000000000000000000000000000000000000000000000000053bcdc" as Hex,
  reputationRegistry: "0x00000000000000000000000000000000000000000000000000000000003029ea" as Hex,
  validationRegistry: "0x000000000000000000000000000000000000000000000000000000000027f902" as Hex,
} as const;

/**
 * Mainnet vanity salts for CREATE2 proxy deployment
 * TBD - need to mine
 */
export const MAINNET_VANITY_SALTS = {
  identityRegistry: "0x000000000000000000000000000000000000000000000000000000000009ec53" as Hex,
  reputationRegistry: "0x000000000000000000000000000000000000000000000000000000000008e99c" as Hex,
  validationRegistry: "0x00000000000000000000000000000000000000000000000000000000000fcb4f" as Hex,
} as const;

/**
 * Implementation salts (same for both testnet and mainnet)
 */
export const IMPLEMENTATION_SALTS = {
  identityRegistry: "0x0000000000000000000000000000000000000000000000000000000000000005" as Hex,
  reputationRegistry: "0x0000000000000000000000000000000000000000000000000000000000000006" as Hex,
  validationRegistry: "0x0000000000000000000000000000000000000000000000000000000000000007" as Hex,
} as const;

/**
 * MinimalUUPS salt (for deploying the MinimalUUPS implementation itself)
 */
export const TESTNET_MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000001" as Hex;
export const MAINNET_MINIMAL_UUPS_SALT = "0x0000000000000000000000000000000000000000000000000000000000000002" as Hex;

/**
 * SAFE Singleton CREATE2 Factory address (same on all chains)
 */
export const SAFE_SINGLETON_FACTORY = "0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7" as const;

/**
 * Expected owner address
 */
export const EXPECTED_OWNER = "0x547289319C3e6aedB179C0b8e8aF0B5ACd062603" as const;

/**
 * Check if a chainId is a mainnet
 */
export function isMainnet(chainId: number): boolean {
  return MAINNET_CHAIN_IDS.includes(chainId);
}

/**
 * Check if a chainId is a testnet
 */
export function isTestnet(chainId: number): boolean {
  return TESTNET_CHAIN_IDS.includes(chainId);
}

/**
 * Validate chainId is in either mainnet or testnet list
 * Throws if chainId is unknown
 */
export function validateChainId(chainId: number): void {
  if (!isMainnet(chainId) && !isTestnet(chainId)) {
    throw new Error(
      `Unknown chainId: ${chainId}. ` +
      `Please add it to MAINNET_CHAIN_IDS or TESTNET_CHAIN_IDS in scripts/addresses.ts`
    );
  }
}

/**
 * Get the network type string
 * Throws if chainId is unknown
 */
export function getNetworkType(chainId: number): "mainnet" | "testnet" {
  validateChainId(chainId);
  return isMainnet(chainId) ? "mainnet" : "testnet";
}

/**
 * Get proxy addresses for a given chainId
 * Throws if chainId is unknown
 */
export function getAddresses(chainId: number) {
  validateChainId(chainId);
  return isMainnet(chainId) ? MAINNET_ADDRESSES : TESTNET_ADDRESSES;
}

/**
 * Get vanity salts for proxy deployment
 * Throws if chainId is unknown
 */
export function getVanitySalts(chainId: number) {
  validateChainId(chainId);
  return isMainnet(chainId) ? MAINNET_VANITY_SALTS : TESTNET_VANITY_SALTS;
}

/**
 * Get the MinimalUUPS contract name for a given chainId
 * Throws if chainId is unknown
 */
export function getMinimalUUPSContract(chainId: number): string {
  validateChainId(chainId);
  return isMainnet(chainId) ? "MinimalUUPSMainnet" : "MinimalUUPS";
}

/**
 * Get the MinimalUUPS salt for a given chainId
 * Throws if chainId is unknown
 */
export function getMinimalUUPSSalt(chainId: number): Hex {
  validateChainId(chainId);
  return isMainnet(chainId) ? MAINNET_MINIMAL_UUPS_SALT : TESTNET_MINIMAL_UUPS_SALT;
}
