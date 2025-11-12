# Vanity Address Deployment Guide

## Overview

Deploy ERC-8004 contracts with vanity addresses (0x8004A, 0x8004B, 0x8004C) using MinimalUUPS placeholder strategy.

## Strategy

1. Deploy proxies with vanity addresses pointing to MinimalUUPS placeholder
2. Deploy actual implementation contracts
3. Upgrade proxies from MinimalUUPS to real implementations

## Prerequisites

- SAFE Singleton Factory at `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
  - Already deployed on mainnet/testnets
  - For localhost: must deploy manually (see below)

## Files Involved

**Contracts:**
- `contracts/MinimalUUPS.sol` - Placeholder UUPS implementation
- `contracts/ERC1967Proxy.sol` - OpenZeppelin proxy wrapper
- `contracts/SingletonFactory.sol` - CREATE2 factory ABI (not deployed, just for interface)

**Scripts:**
- `scripts/find-vanity-salts.ts` - Find salts for vanity addresses
- `scripts/deploy-vanity.ts` - Complete deployment with vanity addresses
- `scripts/deploy-create2-factory.ts` - Deploy factory (localhost only)

## Deployment Steps

### For Localhost Testing

```bash
# 1. Start local node
npx hardhat node

# 2. Deploy CREATE2 factory (localhost only)
npx hardhat run scripts/deploy-create2-factory.ts --network localhost

# 3. Find vanity salts (outputs to console)
npx hardhat run scripts/find-vanity-zero.ts --network localhost

# 4. Copy salts from console output into deploy-vanity.ts (lines 18-31)
#    Update VANITY_SALTS and EXPECTED_ADDRESSES constants

# 5. Deploy everything
npx hardhat run scripts/deploy-vanity.ts --network localhost
```

### For Testnet/Mainnet (e.g., Sepolia)

```bash
# 1. Find vanity salts (outputs to console)
npx hardhat run scripts/find-vanity-zero.ts --network sepolia

# 2. Copy salts from console output into deploy-vanity.ts (lines 18-31)
#    Update VANITY_SALTS and EXPECTED_ADDRESSES constants

# 3. Deploy everything (factory already exists on-chain)
npx hardhat run scripts/deploy-vanity.ts --network sepolia
```

## What deploy-vanity.ts Does

**Phase 1:** Deploy MinimalUUPS placeholder via CREATE2
**Phase 2:** Deploy vanity proxies pointing to MinimalUUPS (0x8004A, 0x8004B, 0x8004C)
**Phase 3:** Deploy real implementation contracts
**Phase 4:** Initialize MinimalUUPS on each proxy (sets msg.sender as owner)
**Phase 5:** Upgrade proxies to real implementations using `upgradeToAndCall()`

## Manual Step Required

After running `find-vanity-zero.ts`, you must **manually copy** the output values into `deploy-vanity.ts`:

```typescript
// Example output from find-vanity-zero.ts:
{
  salts: {
    identity: "0x000000000000000000000000000000000000000000000000000000000003ed12",
    reputation: "0x00000000000000000000000000000000000000000000000000000000001e6f60",
    validation: "0x0000000000000000000000000000000000000000000000000000000000039911"
  },
  addresses: {
    identity: "0x8004A74334E9C8a0787799855FA720bEa2632f28",
    reputation: "0x8004B40CA346bCB6d1c01A8FC0F770602aC1ceB6",
    validation: "0x8004C3478C88560565CE012397ff0139e3721f41"
  }
}
```

Copy these into `deploy-vanity.ts` lines 18-31.

## Network Support

Works on any network where SAFE Singleton Factory is deployed:
- Ethereum Mainnet
- Sepolia, Goerli (testnets)
- Optimism, Arbitrum, Base, Polygon, etc.
- Localhost (after running deploy-create2-factory.ts)

## Result

Three proxies deployed at deterministic vanity addresses (same on all chains):
- **IdentityRegistry**: 0x8004A...
- **ReputationRegistry**: 0x8004B...
- **ValidationRegistry**: 0x8004C...

Each proxy is upgradeable via UUPS pattern and points to the real implementation contracts.
