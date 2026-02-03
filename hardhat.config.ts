import "@nomicfoundation/hardhat-ethers";

import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY || "",
    }
  },
  chainDescriptors: {
    1: {
      name: "Ethereum Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://etherscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    11155111: {
      name: "Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.etherscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    84532: {
      name: "Base Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.basescan.org",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    8453: {
      name: "Base Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://basescan.org",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    80002: {
      name: "Polygon Amoy",
      blockExplorers: {
        etherscan: {
          url: "https://amoy.polygonscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    137: {
      name: "Polygon Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://polygonscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    97: {
      name: "BNB Testnet",
      blockExplorers: {
        etherscan: {
          url: "https://testnet.bscscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    56: {
      name: "BNB Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://bscscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    10143: {
      name: "Monad Testnet",
      blockExplorers: {
        etherscan: {
          url: "https://testnet.monadexplorer.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    143: {
      name: "Monad Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://monadexplorer.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    }
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.24",
        settings: {
          evmVersion: "shanghai",
          optimizer: {
            enabled: true,
            runs: 200,
          },
          viaIR: true,

        },
      },
      production: {
        version: "0.8.24",
        settings: {
          evmVersion: "shanghai",
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
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.SEPOLIA_PRIVATE_KEY ? [process.env.SEPOLIA_PRIVATE_KEY] : [],
    },
    mainnet: {
      type: "http",
      chainType: "l1",
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.MAINNET_PRIVATE_KEY ? [process.env.MAINNET_PRIVATE_KEY] : [],
    },
    baseSepolia: {
      type: "http",
      chainType: "op",
      url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
      accounts: process.env.BASE_SEPOLIA_PRIVATE_KEY ? [process.env.BASE_SEPOLIA_PRIVATE_KEY] : [],
    },
    base: {
      type: "http",
      chainType: "op",
      url: process.env.BASE_RPC_URL || "https://mainnet.base.org",
      accounts: process.env.BASE_PRIVATE_KEY ? [process.env.BASE_PRIVATE_KEY] : [],
    },
    polygonAmoy: {
      type: "http",
      chainType: "l1",
      url: process.env.POLYGON_AMOY_RPC_URL || "https://rpc-amoy.polygon.technology",
      accounts: process.env.POLYGON_AMOY_PRIVATE_KEY ? [process.env.POLYGON_AMOY_PRIVATE_KEY] : [],
    },
    polygon: {
      type: "http",
      chainType: "l1",
      url: process.env.POLYGON_RPC_URL || "https://polygon-rpc.com",
      accounts: process.env.POLYGON_PRIVATE_KEY ? [process.env.POLYGON_PRIVATE_KEY] : [],
    },
    bnbTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.BNB_TESTNET_RPC_URL || "https://bsc-testnet-rpc.publicnode.com",
      accounts: process.env.BNB_TESTNET_PRIVATE_KEY ? [process.env.BNB_TESTNET_PRIVATE_KEY] : [],
    },
    bnb: {
      type: "http",
      chainType: "l1",
      url: process.env.BNB_RPC_URL || "https://bsc-dataseed.binance.org",
      accounts: process.env.BNB_PRIVATE_KEY ? [process.env.BNB_PRIVATE_KEY] : [],
    },
    monadTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.MONAD_TESTNET_RPC_URL || "https://testnet-rpc.monad.xyz",
      accounts: process.env.MONAD_TESTNET_PRIVATE_KEY ? [process.env.MONAD_TESTNET_PRIVATE_KEY] : [],
    },
    monad: {
      type: "http",
      chainType: "l1",
      url: process.env.MONAD_RPC_URL || "https://rpc.monad.xyz",
      accounts: process.env.MONAD_PRIVATE_KEY ? [process.env.MONAD_PRIVATE_KEY] : [],
    },
  },
};

export default config;
