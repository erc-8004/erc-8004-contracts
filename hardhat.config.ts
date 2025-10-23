import "@nomicfoundation/hardhat-ethers";

import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import { configVariable } from "hardhat/config";
import { defineChain } from "viem";

// Define 0G Newton Testnet chain
const zeroGNewton = defineChain({
  id: 16602,
  name: '0G Newton Testnet',
  nativeCurrency: {
    decimals: 18,
    name: '0G',
    symbol: 'A0GI',
  },
  rpcUrls: {
    default: {
      http: ['https://evmrpc-testnet.0g.ai'],
    },
  },
  blockExplorers: {
    default: {
      name: '0G Explorer',
      url: 'https://chainscan-newton.0g.ai',
    },
  },
  testnet: true,
});

const config: HardhatUserConfig = {
  plugins: [hardhatVerify],
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
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    zeroG: {
      type: "http",
      url: "https://evmrpc-testnet.0g.ai",
      accounts: [configVariable("ZEROG_PRIVATE_KEY")],
      chainId: 16602,
    },
  },
  etherscan: {
    apiKey: {
      zeroG: "no-api-key-needed"
    },
    customChains: [
      {
        network: "zeroG",
        chainId: 16602,
        urls: {
          apiURL: "https://chainscan-galileo.0g.ai/open/api",
          browserURL: "https://chainscan-galileo.0g.ai"
        }
      }
    ]
  },
  verify: {
    etherscan: {
      apiKey: "no-api-key-needed",
      customChains: [
        {
          network: "zeroG",
          chainId: 16602,
          urls: {
            apiURL: "https://chainscan-galileo.0g.ai/open/api",
            browserURL: "https://chainscan-galileo.0g.ai"
          }
        }
      ]
    }
  },
  sourcify: {
    enabled: false
  }
};

export default config;
