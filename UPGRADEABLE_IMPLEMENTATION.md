# ERC-8004 Upgradeable Implementation

This document describes the UUPS (Universal Upgradeable Proxy Standard) proxy pattern implementation for the ERC-8004 protocol.

## Overview

The ERC-8004 protocol includes upgradeable versions of all three core registries:
- **IdentityRegistryUpgradeable** - UUPS upgradeable version of the identity registry
- **ReputationRegistryUpgradeable** - UUPS upgradeable version of the reputation registry
- **ValidationRegistryUpgradeable** - UUPS upgradeable version of the validation registry

## Architecture

### UUPS Proxy Pattern

The implementation uses the UUPS (EIP-1822) pattern, which provides:
- **Upgradeability**: Contract logic can be upgraded while preserving state and address
- **Gas efficiency**: Lower deployment costs compared to transparent proxy pattern
- **Security**: Upgrade authorization is part of the implementation contract itself

### Vanity Address Deployment

Proxies are deployed at deterministic vanity addresses using CREATE2:

```
IdentityRegistry:   0x8004A818BFB912233c491871b3d84c89A494BD9e
ReputationRegistry: 0x8004B663056A597Dffe9eCcC1965A193B7388713
ValidationRegistry: 0x8004Cb1BF31DAf7788923b405b754f57acEB4272
Owner:              0x547289319C3e6aedB179C0b8e8aF0B5ACd062603
```

### MinimalUUPS Placeholder Strategy

To achieve deterministic vanity addresses, we use a two-phase deployment:

1. **Phase 1**: Deploy proxies pointing to MinimalUUPS placeholder
   - MinimalUUPS is a minimal UUPS implementation that only stores `_identityRegistry` and owner
   - Proxies get their vanity addresses from CREATE2 salt mining

2. **Phase 2**: Upgrade proxies to real implementations
   - Pre-signed transactions upgrade each proxy
   - Storage (including `_identityRegistry`) persists through upgrade

### Key Components

1. **MinimalUUPS** (`contracts/MinimalUUPS.sol`)
   - Lightweight placeholder implementation
   - Stores `_identityRegistry` at slot 0 (same as real implementations)
   - Allows upgrade to real implementation
   - Owner hardcoded to `0x547289319C3e6aedB179C0b8e8aF0B5ACd062603`

2. **Implementation Contracts** (`contracts/*Upgradeable.sol`)
   - Contains the actual business logic
   - Inherits from OpenZeppelin's upgradeable base contracts
   - Uses `initialize()` function instead of constructor
   - Includes `_authorizeUpgrade()` for upgrade authorization (owner-only)
   - Stores `_identityRegistry` at slot 0 (outside ERC-7201 namespace)

3. **Proxy Contract** (OpenZeppelin's ERC1967Proxy)
   - Delegates all calls to the implementation contract
   - Maintains all storage data
   - Address never changes

4. **Storage Layout**
   - `_identityRegistry` stored at slot 0 (shared between MinimalUUPS and real implementations)
   - All other data stored in ERC-7201 namespaced storage
   - This allows `_identityRegistry` to persist through upgrade

## File Structure

```
contracts/
├── MinimalUUPS.sol                         # Placeholder for vanity deployment
├── IdentityRegistryUpgradeable.sol         # UUPS upgradeable version
├── ReputationRegistryUpgradeable.sol       # UUPS upgradeable version
├── ValidationRegistryUpgradeable.sol       # UUPS upgradeable version
└── ERC1967Proxy.sol                        # Proxy contract wrapper

scripts/
├── deploy-create2-factory.ts               # Deploy CREATE2 factory
├── deploy-vanity.ts                        # Deploy MinimalUUPS + proxies + implementations
├── generate-triple-presigned-upgrade.ts    # Generate pre-signed upgrade transactions
├── upgrade-vanity-presigned.ts             # Broadcast pre-signed upgrades
├── verify-vanity.ts                        # Verify deployment
└── find-vanity-salts-parallel.ts           # Find salts for vanity addresses

test/
├── core.ts                                 # Core contract tests (49 tests)
└── upgradeable.ts                          # Upgradeable-specific tests (27 tests)
```

## Deployment

See [VANITY_DEPLOYMENT_GUIDE.md](./VANITY_DEPLOYMENT_GUIDE.md) for complete deployment instructions.

### Quick Start (Localhost)

```bash
# Start local node
npx hardhat node

# Run full deployment (in another terminal)
npm run local
```

### Quick Start (Testnet/Mainnet)

```bash
# 1. Deploy CREATE2 factory (if needed)
npx hardhat run scripts/deploy-create2-factory.ts --network <network>

# 2. Deploy all contracts
npx hardhat run scripts/deploy-vanity.ts --network <network>

# 3. Generate pre-signed upgrades (requires OWNER_PRIVATE_KEY in .env)
npx hardhat run scripts/generate-triple-presigned-upgrade.ts --network <network>

# 4. Broadcast upgrades
npx hardhat run scripts/upgrade-vanity-presigned.ts --network <network>

# 5. Verify
npx hardhat run scripts/verify-vanity.ts --network <network>
```

## Usage

### Interacting with Deployed Contracts

Always interact with the **proxy addresses**, never the implementation addresses:

```typescript
import hre from "hardhat";

// Get contract instance through proxy
const identityRegistry = await hre.viem.getContractAt(
  "IdentityRegistryUpgradeable",
  "0x8004A818BFB912233c491871b3d84c89A494BD9e"  // Use proxy address
);

// Use normally
const txHash = await identityRegistry.write.register(["ipfs://agent"]);
```

### Upgrading Contracts

To upgrade to a new implementation:

1. Modify the implementation contract (maintaining storage layout)
2. Increment version in `getVersion()`
3. Generate new pre-signed upgrade transactions
4. Broadcast the upgrades

## Key Differences from Original Contracts

### Storage Layout

All upgradeable contracts store `_identityRegistry` at slot 0 (outside ERC-7201 namespace):

```solidity
/// @dev Identity registry address stored at slot 0 (matches MinimalUUPS)
address private _identityRegistry;
```

This allows the value to persist when upgrading from MinimalUUPS to real implementation.

### IdentityRegistryUpgradeable

- Inherits from `Initializable`, `ERC721URIStorageUpgradeable`, `OwnableUpgradeable`, `UUPSUpgradeable`
- Uses `initialize()` instead of constructor
- Constructor includes `_disableInitializers()` to prevent direct initialization
- Added `getVersion()` function for version tracking (currently `1.1.0`)
- Added `_authorizeUpgrade()` for owner-only upgrades

### ReputationRegistryUpgradeable

- `_identityRegistry` stored at slot 0 (not in ERC-7201 namespace)
- Other data stored in ERC-7201 namespaced storage
- Takes `identityRegistry` address in `initialize(address)` instead of constructor
- Added upgrade authorization and versioning

### ValidationRegistryUpgradeable

- `_identityRegistry` stored at slot 0 (not in ERC-7201 namespace)
- Other data stored in ERC-7201 namespaced storage
- Takes `identityRegistry` address in `initialize(address)` instead of constructor
- Added upgrade authorization and versioning

## Security Considerations

### Initialization

- Implementation contracts have constructors that call `_disableInitializers()`
- This prevents anyone from initializing the implementation directly
- Proxies call `initialize()` during deployment
- `initialize()` can only be called once per proxy (enforced by `initializer` modifier)

### Upgrade Authorization

- Only the contract owner can authorize upgrades via `_authorizeUpgrade()`
- Upgrade function (`upgradeToAndCall()`) is inherited from `UUPSUpgradeable`
- Owner is set during MinimalUUPS initialization

### Storage Safety

- `_identityRegistry` at slot 0 persists through upgrades
- All other data uses ERC-7201 namespaced storage
- Future upgrades must maintain storage layout of previous versions

## Testing

```bash
npm run test
```

Runs both test suites:
- `test/core.ts` - 49 tests for core functionality
- `test/upgradeable.ts` - 27 tests for upgradeable-specific behavior

## Version Management

Each upgradeable contract includes a `getVersion()` function:

```solidity
function getVersion() external pure returns (string memory) {
    return "1.1.0";
}
```

When upgrading, increment this version number to track deployed versions.

## Gas Considerations

### Deployment

- Upgradeable contracts have higher deployment costs due to:
  - Additional inherited contracts (Initializable, UUPSUpgradeable, etc.)
  - Proxy contract deployment
  - Extra storage for upgrade logic

### Runtime

- Minimal gas overhead for regular operations
- Proxy adds a single delegatecall per transaction (~700 gas)

### Upgrade Costs

- New implementation deployment
- `upgradeToAndCall()` transaction per proxy
- No migration of existing data required

## Best Practices

### For Developers

1. **Never deploy and use implementation contracts directly**
   - Always interact through proxy addresses
   - Implementation addresses are for upgrade purposes only

2. **Test thoroughly before upgrading**
   - Deploy to testnet first
   - Verify all functionality works
   - Check storage persistence

3. **Maintain storage layout**
   - Keep `_identityRegistry` at slot 0
   - Never remove or reorder existing storage variables
   - Only add new storage variables at the end of namespaced structs

4. **Version your implementations**
   - Update `getVersion()` for each new implementation
   - Keep track of which versions are deployed where

### For Operators

1. **Secure owner keys**
   - Owner can upgrade contracts
   - Use multi-sig or timelock for production
   - Consider transferring ownership to governance

2. **Monitor after upgrades**
   - Verify version changed correctly
   - Check that all functions still work
   - Monitor for unexpected behavior

## Resources

- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/5.x/upgradeable)
- [UUPS Proxy Pattern](https://eips.ethereum.org/EIPS/eip-1822)
- [EIP-1967 Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
- [ERC-7201 Namespaced Storage](https://eips.ethereum.org/EIPS/eip-7201)

## License

CC0 - Public Domain (same as ERC-8004)
