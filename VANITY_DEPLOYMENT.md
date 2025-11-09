# ERC-8004 Vanity Address Deployment

## Summary

This document contains the vanity salts and addresses for deploying the ERC-8004 registries with custom addresses starting with `0x8004A`, `0x8004B`, and `0x8004C`.

## Vanity Proxy Addresses

All proxies will be deployed at these addresses on **ANY network**:

- **IdentityRegistry**: `0x8004A501bddE7AAFd13F5200E9AA77D61C185684`
- **ReputationRegistry**: `0x8004Bd1125733a0eD390E209aaB549D01263061e`
- **ValidationRegistry**: `0x8004C1EDDc74bB127C9E10D291DB07abbBE34be4`

## CREATE2 Salts

### Proxy Salts (for vanity addresses)

All proxies initially point to placeholder address `0x0000000000000000000000000000000000008004`:

```typescript
const VANITY_SALTS = {
  identityRegistry: "0x0000000000000000000000000000000000000000000000000000000000181f62",
  reputationRegistry: "0x000000000000000000000000000000000000000000000000000000000010a275",
  validationRegistry: "0x00000000000000000000000000000000000000000000000000000000001138b5",
};
```

## Deployment Process

### Prerequisites

1. SAFE Singleton CREATE2 Factory must be deployed at: `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
   - For localhost: Run `npx hardhat run scripts/deploy-create2-factory.ts --network localhost`
   - For mainnet/testnets: Usually already deployed

### Steps

1. **Deploy Vanity Proxies** (pointing to placeholder `0x...8004`)
   - Use the salts above with CREATE2 factory
   - Proxies will be deployed at the vanity addresses

2. **Deploy Implementation Contracts**
   - Deploy `IdentityRegistryUpgradeable`
   - Deploy `ReputationRegistryUpgradeable`
   - Deploy `ValidationRegistryUpgradeable`

3. **Upgrade Proxies**
   - Call `upgradeToAndCall()` on each proxy to point to real implementations
   - Pass initialization data in the same transaction

### Deployment Script

Use: `npx hardhat run scripts/deploy-vanity.ts --network <network>`

## Network Compatibility

These vanity addresses will be **identical on all networks** because:

1. CREATE2 factory address is always the same: `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7`
2. Proxy bytecode is deterministic (points to `0x...8004` placeholder)
3. Salts are network-independent

## Verification

After deployment, verify that:

1. All three proxies are deployed at the correct vanity addresses
2. Each proxy correctly points to its implementation contract
3. Each contract is properly initialized
4. ReputationRegistry and ValidationRegistry reference the IdentityRegistry proxy

## Scripts

- `scripts/find-vanity-zero.ts` - Find vanity salts (already found, no need to run again)
- `scripts/deploy-vanity.ts` - Complete deployment with vanity addresses
- `scripts/deploy-create2-factory.ts` - Deploy CREATE2 factory (localhost only)

## Notes

- Implementation addresses will vary by network (they don't need vanity addresses)
- Only proxy addresses have vanity prefixes (`0x8004A`, `0x8004B`, `0x8004C`)
- Proxies are upgradeable via UUPS pattern
- Owner can upgrade implementation contracts while keeping the same proxy addresses
