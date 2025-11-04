import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";

import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import { defineChain } from "viem";

const SEPOLIA_RPC_URL = configVariable("SEPOLIA_RPC_URL");
const SEPOLIA_PRIVATE_KEY = configVariable("SEPOLIA_PRIVATE_KEY");
const BASE_SEPOLIA_RPC_URL = "https://sepolia.base.org";
const LINEA_SEPOLIA_RPC_URL = "https://rpc.sepolia.linea.build";
const AMOY_SEPOLIA_RPC_URL = "https://rpc-amoy.polygon.technology";
const HYPERLIQUID_TESTNET_RPC_URL = "https://rpc.hyperliquid-testnet.xyz/evm";
const SKALE_BASE_SEPOLIA_RPC_URL = "https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";

const skaleBaseSepolia = defineChain({
  id: 324705682,
  name: "SKALE Base Sepolia Testnet",
  nativeCurrency: { name: "sFUEL", symbol: "sFUEL", decimals: 18 },
  rpcUrls: {
    default: { http: [SKALE_BASE_SEPOLIA_RPC_URL] },
  },
  blockExplorers: {
    default: {
      name: "SKALE Explorer",
      url: "https://base-sepolia-testnet-explorer.skalenodes.com",
    },
  },
  testnet: true,
});

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  viemConfig: {
    chains: [skaleBaseSepolia],
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,
        },
      },
      polygon: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
          viaIR: true,
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: SEPOLIA_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    baseSepolia: {
      type: "http",
      chainType: "op",
      url: BASE_SEPOLIA_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    lineaSepolia: {
      type: "http",
      chainType: "l1",
      url: LINEA_SEPOLIA_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    amoySepolia: {
      type: "http",
      chainType: "l1",
      url: AMOY_SEPOLIA_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    hyperliquidTestnet: {
      type: "http",
      chainType: "l1",
      url: HYPERLIQUID_TESTNET_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
    },
    skaleBaseSepolia: {
      type: "http",
      chainType: "l1",
      url: SKALE_BASE_SEPOLIA_RPC_URL,
      accounts: [SEPOLIA_PRIVATE_KEY],
      chain: skaleBaseSepolia,
    },
  },
  chainDescriptors: {
    84532: {
      name: "baseSepolia",
      blockExplorers: {
        etherscan: {
          name: "BaseScan",
          url: "https://sepolia-explorer.base.org",
          apiUrl: "https://api-sepolia.basescan.org/api",
        },
      },
    },
    59141: {
      name: "lineaSepolia",
      blockExplorers: {
        etherscan: {
          name: "LineaScan",
          url: "https://sepolia.lineascan.build",
          apiUrl: "https://api-sepolia.lineascan.build/api",
        },
      },
    },
    80002: {
      name: "amoySepolia",
      blockExplorers: {
        etherscan: {
          name: "PolygonScan",
          url: "https://amoy.polygonscan.com",
          apiUrl: "https://api-amoy.polygonscan.com/api",
        },
      },
    },
    998: {
      name: "hyperliquidTestnet",
      blockExplorers: {},
    },
    324705682: {
      name: "skaleBaseSepolia",
      blockExplorers: {
        etherscan: {
          name: "Skale Explorer",
          url: "https://base-sepolia-testnet-explorer.skalenodes.com",
          apiUrl: "https://base-sepolia-testnet-explorer.skalenodes.com/api",
        },
      },
    },
  },
  verify: {
    etherscan: {
      apiKey: ETHERSCAN_API_KEY,
    },
  }
};

export default config;
