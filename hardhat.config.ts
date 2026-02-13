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
    },
    sourcify: {
      enabled: true,
      apiUrl: "https://sourcify-api-monad.blockvision.org/",
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
    },
    534352: {
      name: "Scroll Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://scrollscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    534351: {
      name: "Scroll Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.scrollscan.com",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    100: {
      name: "Gnosis Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://gnosisscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    10200: {
      name: "Gnosis Chiado",
      blockExplorers: {
        etherscan: {
          url: "https://gnosis-chiado.blockscout.com",
          apiUrl: "https://gnosis-chiado.blockscout.com/api",
        }
      }
    },
    42161: {
      name: "Arbitrum One",
      blockExplorers: {
        etherscan: {
          url: "https://arbiscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    421614: {
      name: "Arbitrum Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.arbiscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    42220: {
      name: "Celo Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://celoscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    11142220: {
      name: "Celo Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://celo-sepolia.blockscout.com",
          apiUrl: "https://celo-sepolia.blockscout.com/api",
        }
      }
    },
    167000: {
      name: "Taiko Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://taikoscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    167012: {
      name: "Taiko Hoodi",
      blockExplorers: {
        etherscan: {
          url: "https://hoodi.taikoscan.io",
          apiUrl: "https://hoodi.taikoscan.io/api",
        }
      }
    },
    4326: {
      name: "MegaETH",
      blockExplorers: {
        blockscout: {
          url: "https://megaeth.blockscout.com",
          apiUrl: "https://megaeth.blockscout.com/api",
        }
      }
    },
    6343: {
      name: "MegaETH Testnet",
      blockExplorers: {
        blockscout: {
          url: "https://megaeth-testnet-v2.blockscout.com",
          apiUrl: "https://megaeth-testnet-v2.blockscout.com/api",
        }
      }
    },
    59144: {
      name: "Linea Mainnet",
      blockExplorers: {
        etherscan: {
          url: "https://lineascan.build",
          apiUrl: "https://api.lineascan.build/api",
        }
      }
    },
    59141: {
      name: "Linea Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.lineascan.build",
          apiUrl: "https://api-sepolia.lineascan.build/api",
        }
      }
    },
    43114: {
      name: "Avalanche C-Chain",
      blockExplorers: {
        etherscan: {
          url: "https://snowtrace.io",
          apiUrl: "https://api.snowtrace.io/api",
        }
      }
    },
    43113: {
      name: "Avalanche Fuji",
      blockExplorers: {
        etherscan: {
          url: "https://testnet.snowtrace.io",
          apiUrl: "https://api-testnet.snowtrace.io/api",
        }
      }
    },
    10: {
      name: "Optimism",
      blockExplorers: {
        etherscan: {
          url: "https://optimistic.etherscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    11155420: {
      name: "OP Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia-optimism.etherscan.io",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    196: {
      name: "XLayer",
      blockExplorers: {
        etherscan: {
          url: "https://www.oklink.com/xlayer",
          apiUrl: "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/XLAYER",
        }
      }
    },
    1952: {
      name: "XLayer Testnet",
      blockExplorers: {
        etherscan: {
          url: "https://www.oklink.com/xlayer-test",
          apiUrl: "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/XLAYER_TESTNET",
        }
      }
    },
    2741: {
      name: "Abstract",
      blockExplorers: {
        etherscan: {
          url: "https://abscan.org",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    11124: {
      name: "Abstract Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.abscan.org",
          apiUrl: "https://api.etherscan.io/v2/api",
        }
      }
    },
    5000: {
      name: "Mantle",
      blockExplorers: {
        etherscan: {
          url: "https://mantlescan.xyz",
          apiUrl: "https://api.mantlescan.xyz/api",
        }
      }
    },
    5003: {
      name: "Mantle Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia.mantlescan.xyz",
          apiUrl: "https://api-sepolia.mantlescan.xyz/api",
        }
      }
    },
    1868: {
      name: "Soneium",
      blockExplorers: {
        etherscan: {
          url: "https://soneium.blockscout.com",
          apiUrl: "https://soneium.blockscout.com/api",
        },
        blockscout: {
          url: "https://soneium.blockscout.com",
          apiUrl: "https://soneium.blockscout.com/api",
        }
      }
    },
    1946: {
      name: "Soneium Minato",
      blockExplorers: {
        etherscan: {
          url: "https://soneium-minato.blockscout.com",
          apiUrl: "https://soneium-minato.blockscout.com/api",
        },
        blockscout: {
          url: "https://soneium-minato.blockscout.com",
          apiUrl: "https://soneium-minato.blockscout.com/api",
        }
      }
    },
    2345: {
      name: "GOAT Network",
      blockExplorers: {
        etherscan: {
          url: "https://explorer.goat.network",
          apiUrl: "https://explorer.goat.network/api",
        },
        blockscout: {
          url: "https://explorer.goat.network",
          apiUrl: "https://explorer.goat.network/api",
        }
      }
    },
    48816: {
      name: "GOAT Testnet3",
      blockExplorers: {
        etherscan: {
          url: "https://explorer.testnet3.goat.network",
          apiUrl: "https://explorer.testnet3.goat.network/api",
        },
        blockscout: {
          url: "https://explorer.testnet3.goat.network",
          apiUrl: "https://explorer.testnet3.goat.network/api",
        }
      }
    },
    1088: {
      name: "Metis Andromeda",
      blockExplorers: {
        etherscan: {
          url: "https://andromeda-explorer.metis.io",
          apiUrl: "https://andromeda-explorer.metis.io/api",
        },
        blockscout: {
          url: "https://andromeda-explorer.metis.io",
          apiUrl: "https://andromeda-explorer.metis.io/api",
        }
      }
    },
    59902: {
      name: "Metis Sepolia",
      blockExplorers: {
        etherscan: {
          url: "https://sepolia-explorer.metisdevops.link",
          apiUrl: "https://sepolia-explorer.metisdevops.link/api",
        },
        blockscout: {
          url: "https://sepolia-explorer.metisdevops.link",
          apiUrl: "https://sepolia-explorer.metisdevops.link/api",
        }
      }
    },
    295: {
      name: "Hedera",
      blockExplorers: {
        etherscan: {
          url: "https://hashscan.io/mainnet",
          apiUrl: "https://hashscan.io/api/v1",
        }
      }
    },
    296: {
      name: "Hedera Testnet",
      blockExplorers: {
        etherscan: {
          url: "https://hashscan.io/testnet",
          apiUrl: "https://hashscan.io/api/v1",
        }
      }
    },
    1187947933: {
      name: "SKALE Base",
      blockExplorers: {
        blockscout: {
          url: "https://skale-base-explorer.skalenodes.com",
          apiUrl: "https://skale-base-explorer.skalenodes.com/api",
        }
      }
    },
    324705682: {
      name: "SKALE Base Sepolia",
      blockExplorers: {
        blockscout: {
          url: "https://base-sepolia-testnet-explorer.skalenodes.com",
          apiUrl: "https://base-sepolia-testnet-explorer.skalenodes.com/api",
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
    scrollSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.SCROLL_SEPOLIA_RPC_URL || "https://sepolia-rpc.scroll.io",
      accounts: process.env.SCROLL_SEPOLIA_PRIVATE_KEY ? [process.env.SCROLL_SEPOLIA_PRIVATE_KEY] : [],
    },
    scroll: {
      type: "http",
      chainType: "l1",
      url: process.env.SCROLL_RPC_URL || "https://rpc.scroll.io",
      accounts: process.env.SCROLL_PRIVATE_KEY ? [process.env.SCROLL_PRIVATE_KEY] : [],
    },
    gnosisChiado: {
      type: "http",
      chainType: "l1",
      url: process.env.GNOSIS_CHIADO_RPC_URL || "https://rpc.chiadochain.net",
      accounts: process.env.GNOSIS_CHIADO_PRIVATE_KEY ? [process.env.GNOSIS_CHIADO_PRIVATE_KEY] : [],
    },
    gnosis: {
      type: "http",
      chainType: "l1",
      url: process.env.GNOSIS_RPC_URL || "https://rpc.gnosischain.com",
      accounts: process.env.GNOSIS_PRIVATE_KEY ? [process.env.GNOSIS_PRIVATE_KEY] : [],
    },
    arbitrumSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.ARBITRUM_SEPOLIA_RPC_URL || "https://sepolia-rollup.arbitrum.io/rpc",
      accounts: process.env.ARBITRUM_SEPOLIA_PRIVATE_KEY ? [process.env.ARBITRUM_SEPOLIA_PRIVATE_KEY] : [],
    },
    arbitrum: {
      type: "http",
      chainType: "l1",
      url: process.env.ARBITRUM_RPC_URL || "https://arb1.arbitrum.io/rpc",
      accounts: process.env.ARBITRUM_PRIVATE_KEY ? [process.env.ARBITRUM_PRIVATE_KEY] : [],
    },
    celoSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.CELO_SEPOLIA_RPC_URL || "https://forno.celo-sepolia.celo-testnet.org",
      accounts: process.env.CELO_SEPOLIA_PRIVATE_KEY ? [process.env.CELO_SEPOLIA_PRIVATE_KEY] : [],
    },
    celo: {
      type: "http",
      chainType: "l1",
      url: process.env.CELO_RPC_URL || "https://forno.celo.org",
      accounts: process.env.CELO_PRIVATE_KEY ? [process.env.CELO_PRIVATE_KEY] : [],
    },
    taikoHoodi: {
      type: "http",
      chainType: "l1",
      url: process.env.TAIKO_HOODI_RPC_URL || "https://rpc.hoodi.taiko.xyz",
      accounts: process.env.TAIKO_HOODI_PRIVATE_KEY ? [process.env.TAIKO_HOODI_PRIVATE_KEY] : [],
    },
    taiko: {
      type: "http",
      chainType: "l1",
      url: process.env.TAIKO_RPC_URL || "https://rpc.mainnet.taiko.xyz",
      accounts: process.env.TAIKO_PRIVATE_KEY ? [process.env.TAIKO_PRIVATE_KEY] : [],
    },
    megaeth: {
      type: "http",
      chainType: "l1",
      url: process.env.MEGAETH_RPC_URL || "https://alpha.megaeth.com/rpc",
      accounts: process.env.MEGAETH_PRIVATE_KEY ? [process.env.MEGAETH_PRIVATE_KEY] : [],
    },
    megaethTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.MEGAETH_TESTNET_RPC_URL || "https://timothy.megaeth.com/rpc",
      accounts: process.env.MEGAETH_TESTNET_PRIVATE_KEY ? [process.env.MEGAETH_TESTNET_PRIVATE_KEY] : [],
    },
    lineaSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.LINEA_SEPOLIA_RPC_URL || "https://rpc.sepolia.linea.build",
      accounts: process.env.LINEA_SEPOLIA_PRIVATE_KEY ? [process.env.LINEA_SEPOLIA_PRIVATE_KEY] : [],
    },
    linea: {
      type: "http",
      chainType: "l1",
      url: process.env.LINEA_RPC_URL || "https://rpc.linea.build",
      accounts: process.env.LINEA_PRIVATE_KEY ? [process.env.LINEA_PRIVATE_KEY] : [],
    },
    avalancheFuji: {
      type: "http",
      chainType: "l1",
      url: process.env.AVALANCHE_FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: process.env.AVALANCHE_FUJI_PRIVATE_KEY ? [process.env.AVALANCHE_FUJI_PRIVATE_KEY] : [],
    },
    avalanche: {
      type: "http",
      chainType: "l1",
      url: process.env.AVALANCHE_RPC_URL || "https://api.avax.network/ext/bc/C/rpc",
      accounts: process.env.AVALANCHE_PRIVATE_KEY ? [process.env.AVALANCHE_PRIVATE_KEY] : [],
    },
    opSepolia: {
      type: "http",
      chainType: "op",
      url: process.env.OP_SEPOLIA_RPC_URL || "https://sepolia.optimism.io",
      accounts: process.env.OP_SEPOLIA_PRIVATE_KEY ? [process.env.OP_SEPOLIA_PRIVATE_KEY] : [],
    },
    op: {
      type: "http",
      chainType: "op",
      url: process.env.OP_MAINNET_RPC_URL || "https://mainnet.optimism.io",
      accounts: process.env.OP_MAINNET_PRIVATE_KEY ? [process.env.OP_MAINNET_PRIVATE_KEY] : [],
    },
    xlayer: {
      type: "http",
      chainType: "l1",
      url: process.env.XLAYER_RPC_URL || "https://rpc.xlayer.tech",
      accounts: process.env.XLAYER_PRIVATE_KEY ? [process.env.XLAYER_PRIVATE_KEY] : [],
    },
    xlayerTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.XLAYER_TESTNET_RPC_URL || "https://testrpc.xlayer.tech",
      accounts: process.env.XLAYER_TESTNET_PRIVATE_KEY ? [process.env.XLAYER_TESTNET_PRIVATE_KEY] : [],
    },
    abstract: {
      type: "http",
      chainType: "l1",
      url: process.env.ABSTRACT_RPC_URL || "https://api.mainnet.abs.xyz",
      accounts: process.env.ABSTRACT_PRIVATE_KEY ? [process.env.ABSTRACT_PRIVATE_KEY] : [],
    },
    abstractSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.ABSTRACT_SEPOLIA_RPC_URL || "https://api.testnet.abs.xyz",
      accounts: process.env.ABSTRACT_SEPOLIA_PRIVATE_KEY ? [process.env.ABSTRACT_SEPOLIA_PRIVATE_KEY] : [],
    },
    mantleSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.MANTLE_SEPOLIA_RPC_URL || "https://rpc.sepolia.mantle.xyz",
      accounts: process.env.MANTLE_SEPOLIA_PRIVATE_KEY ? [process.env.MANTLE_SEPOLIA_PRIVATE_KEY] : [],
    },
    mantle: {
      type: "http",
      chainType: "l1",
      url: process.env.MANTLE_RPC_URL || "https://rpc.mantle.xyz",
      accounts: process.env.MANTLE_PRIVATE_KEY ? [process.env.MANTLE_PRIVATE_KEY] : [],
    },
    soneiumMinato: {
      type: "http",
      chainType: "op",
      url: process.env.SONEIUM_MINATO_RPC_URL || "https://rpc.minato.soneium.org",
      accounts: process.env.SONEIUM_MINATO_PRIVATE_KEY ? [process.env.SONEIUM_MINATO_PRIVATE_KEY] : [],
    },
    soneium: {
      type: "http",
      chainType: "op",
      url: process.env.SONEIUM_RPC_URL || "https://rpc.soneium.org",
      accounts: process.env.SONEIUM_PRIVATE_KEY ? [process.env.SONEIUM_PRIVATE_KEY] : [],
    },
    goatTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.GOAT_TESTNET_RPC_URL || "https://rpc.testnet3.goat.network",
      accounts: process.env.GOAT_TESTNET_PRIVATE_KEY ? [process.env.GOAT_TESTNET_PRIVATE_KEY] : [],
    },
    goat: {
      type: "http",
      chainType: "l1",
      url: process.env.GOAT_RPC_URL || "https://rpc.goat.network",
      accounts: process.env.GOAT_PRIVATE_KEY ? [process.env.GOAT_PRIVATE_KEY] : [],
    },
    metis: {
      type: "http",
      chainType: "l1",
      url: process.env.METIS_RPC_URL || "https://andromeda.metis.io/?owner=1088",
      accounts: process.env.METIS_PRIVATE_KEY ? [process.env.METIS_PRIVATE_KEY] : [],
    },
    metisSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.METIS_SEPOLIA_RPC_URL || "https://sepolia.metisdevops.link",
      accounts: process.env.METIS_SEPOLIA_PRIVATE_KEY ? [process.env.METIS_SEPOLIA_PRIVATE_KEY] : [],
    },
    hedera: {
      type: "http",
      chainType: "l1",
      url: process.env.HEDERA_RPC_URL || "https://mainnet.hashio.io/api",
      accounts: process.env.HEDERA_PRIVATE_KEY ? [process.env.HEDERA_PRIVATE_KEY] : [],
    },
    hederaTestnet: {
      type: "http",
      chainType: "l1",
      url: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
      accounts: process.env.HEDERA_TESTNET_PRIVATE_KEY ? [process.env.HEDERA_TESTNET_PRIVATE_KEY] : [],
    },
    skaleBaseSepolia: {
      type: "http",
      chainType: "l1",
      url: process.env.SKALE_BASE_SEPOLIA_RPC_URL || "https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha",
      accounts: process.env.SKALE_BASE_SEPOLIA_PRIVATE_KEY ? [process.env.SKALE_BASE_SEPOLIA_PRIVATE_KEY] : [],
    },
    skaleBase: {
      type: "http",
      chainType: "l1",
      url: process.env.SKALE_BASE_RPC_URL || "https://skale-base.skalenodes.com/v1/base",
      accounts: process.env.SKALE_BASE_PRIVATE_KEY ? [process.env.SKALE_BASE_PRIVATE_KEY] : [],
    },
  },
};

export default config;
