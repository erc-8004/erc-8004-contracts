# Vanity Address Deployment Guide

## Overview

Deploy ERC-8004 contracts with vanity addresses (`0x8004A`, `0x8004B`, `0x8004C`) using MinimalUUPS placeholder strategy.

## Strategy

1. Deploy MinimalUUPS placeholder via CREATE2
2. Deploy proxies with vanity addresses pointing to MinimalUUPS
3. Deploy real implementation contracts via CREATE2
4. Upgrade proxies from MinimalUUPS to real implementations (via pre-signed transactions)

## Key Addresses (Deterministic Across All Networks)

```
CREATE2 Factory:    0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
MinimalUUPS:        0xd53dE688e0b0ad436FBdbDa00036832FF6499234
IdentityRegistry:   0x8004A818BFB912233c491871b3d84c89A494BD9e
ReputationRegistry: 0x8004B663056A597Dffe9eCcC1965A193B7388713
ValidationRegistry: 0x8004Cb1BF31DAf7788923b405b754f57acEB4272
Owner:              0x547289319C3e6aedB179C0b8e8aF0B5ACd062603
```

## Prerequisites

- SAFE Singleton Factory at `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
  - Already deployed on mainnet/testnets
  - For localhost: deploy via `scripts/deploy-create2-factory.ts`
- `OWNER_PRIVATE_KEY` in `.env` for generating pre-signed transactions

## Files Involved

**Contracts:**
- `contracts/MinimalUUPS.sol` - Placeholder UUPS implementation (stores `_identityRegistry` at slot 0)
- `contracts/IdentityRegistryUpgradeable.sol` - Real identity registry implementation
- `contracts/ReputationRegistryUpgradeable.sol` - Real reputation registry implementation
- `contracts/ValidationRegistryUpgradeable.sol` - Real validation registry implementation

**Scripts:**
- `scripts/deploy-create2-factory.ts` - Deploy CREATE2 factory (once per network)
- `scripts/deploy-vanity.ts` - Deploy MinimalUUPS, proxies, and implementations
- `scripts/generate-triple-presigned-upgrade.ts` - Generate pre-signed upgrade transactions
- `scripts/upgrade-vanity-presigned.ts` - Broadcast pre-signed upgrades
- `scripts/verify-vanity.ts` - Verify deployment is correct
- `scripts/find-vanity-salts-parallel.ts` - Find salts for vanity addresses (only if bytecode changes)

## Deployment Steps

### Complete Flow (New Network)

```bash
# 1. Deploy CREATE2 factory (if not already on network)
npx hardhat run scripts/deploy-create2-factory.ts --network <network>

# 2. Deploy all contracts (MinimalUUPS + proxies + implementations)
npx hardhat run scripts/deploy-vanity.ts --network <network>

# 3. Generate pre-signed upgrade transactions (requires OWNER_PRIVATE_KEY in .env)
npx hardhat run scripts/generate-triple-presigned-upgrade.ts --network <network>

# 4. Broadcast the upgrades
npx hardhat run scripts/upgrade-vanity-presigned.ts --network <network>

# 5. Verify everything
npx hardhat run scripts/verify-vanity.ts --network <network>
```

### For Localhost Testing

```bash
# Start local node
npx hardhat node

# Run full deployment (in another terminal)
npm run local
```

The `npm run local` command runs:
1. `local:factory` - Deploy CREATE2 factory
2. `local:vanity` - Deploy + upgrade + verify

## What Each Script Does

### deploy-create2-factory.ts

Deploys the SAFE Singleton Factory using a pre-signed transaction. The factory always deploys to `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7` on any chain.

### deploy-vanity.ts

**Phase 1:** Deploy MinimalUUPS placeholder via CREATE2
- Single instance at `0xd53dE688e0b0ad436FBdbDa00036832FF6499234`
- Stores `_identityRegistry` at slot 0 (matches real implementations)

**Phase 2:** Deploy vanity proxies
- IdentityRegistry proxy at `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- ReputationRegistry proxy at `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- ValidationRegistry proxy at `0x8004Cb1BF31DAf7788923b405b754f57acEB4272`
- All point to MinimalUUPS initially
- Owner set to `0x547289319C3e6aedB179C0b8e8aF0B5ACd062603`

**Phase 3:** Deploy real implementations via CREATE2
- IdentityRegistryUpgradeable
- ReputationRegistryUpgradeable
- ValidationRegistryUpgradeable

### generate-triple-presigned-upgrade.ts

Creates 3 signed transactions (nonces 0, 1, 2) that upgrade each proxy to its real implementation. Outputs `triple-presigned-upgrade-chain-<chainId>.json`.

**Requires:** `OWNER_PRIVATE_KEY` in `.env`

### upgrade-vanity-presigned.ts

1. Loads pre-signed transactions from JSON file
2. Funds owner address if needed
3. Broadcasts all 3 upgrade transactions
4. Verifies upgrades succeeded

### verify-vanity.ts

Comprehensive verification:
1. Proxy addresses have code
2. Contract versions are correct (1.1.0)
3. Ownership is correct
4. Implementation addresses are correct
5. Cross-registry references work (ReputationRegistry/ValidationRegistry -> IdentityRegistry)

### find-vanity-salts-parallel.ts

Searches for CREATE2 salts that produce vanity addresses. Uses parallel workers for speed.

**Only needed if:**
- First time setting up from scratch
- MinimalUUPS bytecode changes
- Proxy bytecode changes

Current salts are already in `deploy-vanity.ts`.

## Storage Layout

MinimalUUPS and real implementations share the same storage layout for `_identityRegistry`:

```
Slot 0: _identityRegistry (address)
```

This allows the `_identityRegistry` value to persist through the upgrade from MinimalUUPS to real implementation.

Other data (feedback, validations, etc.) is stored in ERC-7201 namespaced storage.

## Network Support

Works on any network where SAFE Singleton Factory is deployed:
- Ethereum Mainnet
- Sepolia, Goerli (testnets)
- Optimism, Arbitrum, Base, Polygon, etc.
- Localhost (after running deploy-create2-factory.ts)

## Result

Three proxies deployed at deterministic vanity addresses (same on all chains):
- **IdentityRegistry**: `0x8004A818BFB912233c491871b3d84c89A494BD9e`
- **ReputationRegistry**: `0x8004B663056A597Dffe9eCcC1965A193B7388713`
- **ValidationRegistry**: `0x8004Cb1BF31DAf7788923b405b754f57acEB4272`

Each proxy is upgradeable via UUPS pattern and owned by `0x547289319C3e6aedB179C0b8e8aF0B5ACd062603`.
