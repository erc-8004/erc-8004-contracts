# ERC-8004 Upgradeable Implementation

This document describes the UUPS (Universal Upgradeable Proxy Standard) proxy pattern implementation for the ERC-8004 protocol.

## Overview

The ERC-8004 protocol now includes upgradeable versions of all three core registries:

- **IdentityRegistryUpgradeable** - UUPS upgradeable version of the identity registry
- **ReputationRegistryUpgradeable** - UUPS upgradeable version of the reputation registry
- **ValidationRegistryUpgradeable** - UUPS upgradeable version of the validation registry

## Architecture

### UUPS Proxy Pattern

The implementation uses the UUPS (EIP-1822) pattern, which provides:

- **Upgradeability**: Contract logic can be upgraded while preserving state and address
- **Gas efficiency**: Lower deployment costs compared to transparent proxy pattern
- **Security**: Upgrade authorization is part of the implementation contract itself

### Key Components

1. **Implementation Contracts** (`contracts/*Upgradeable.sol`)

   - Contains the actual business logic
   - Inherits from OpenZeppelin's upgradeable base contracts
   - Uses `initialize()` function instead of constructor
   - Includes `_authorizeUpgrade()` for upgrade authorization (owner-only)

2. **Proxy Contract** (`contracts/ERC1967Proxy.sol`)

   - Lightweight wrapper around OpenZeppelin's ERC1967Proxy
   - Delegates all calls to the implementation contract
   - Maintains all storage data
   - Address never changes

3. **Storage Layout**
   - All upgradeable contracts use OpenZeppelin's storage-safe patterns
   - `_disableInitializers()` in constructor prevents implementation initialization
   - Proper initialization through proxy

## File Structure

```
contracts/
├── IdentityRegistry.sol                    # Original non-upgradeable version
├── ReputationRegistry.sol                  # Original non-upgradeable version
├── ValidationRegistry.sol                  # Original non-upgradeable version
├── IdentityRegistryUpgradeable.sol         # UUPS upgradeable version
├── ReputationRegistryUpgradeable.sol       # UUPS upgradeable version
├── ValidationRegistryUpgradeable.sol       # UUPS upgradeable version
└── ERC1967Proxy.sol                        # Proxy contract wrapper

scripts/
└── upgrade-contracts.ts                    # Script to upgrade existing proxies

ignition/
└── modules/
    ├── ERC8004.ts                          # Original deployment module
    └── ERC8004Upgradeable.ts               # Upgradeable deployment module

test/
├── ERC8004.ts                              # Original test suite (40 tests - all passing)
└── ERC8004Upgradeable.ts                   # Upgradeable-specific tests
```

## Deployment

### Using Hardhat Ignition

```bash
# Deploy upgradeable contracts
npx hardhat ignition deploy ./ignition/modules/ERC8004Upgradeable.ts --network <network>
```

The deployment process:

1. Deploys implementation contracts
2. Deploys ERC1967Proxy for each implementation
3. Initializes each proxy with appropriate parameters
4. Verifies deployment and returns proxy addresses

## Usage

### Interacting with Deployed Contracts

Always interact with the **proxy addresses**, never the implementation addresses directly:

```typescript
import hre from "hardhat";

// Get contract instance through proxy
const identityRegistry = await hre.viem.getContractAt(
  "IdentityRegistryUpgradeable",
  PROXY_ADDRESS // Use proxy address
);

// Use normally
const txHash = await identityRegistry.write.register(["ipfs://agent"]);
```

### Upgrading Contracts

To upgrade to a new implementation:

1. Update the proxy addresses in `scripts/upgrade-contracts.ts`
2. Modify the implementation contract as needed (maintaining storage layout)
3. Run the upgrade script:

```bash
npx hardhat run scripts/upgrade-contracts.ts --network <network>
```

The upgrade process:

1. Deploys new implementation contracts
2. Calls `upgradeToAndCall()` on each proxy (owner-only)
3. Verifies upgrade success
4. All storage data is preserved

## Key Differences from Original Contracts

### IdentityRegistryUpgradeable

- Inherits from `Initializable`, `ERC721URIStorageUpgradeable`, `OwnableUpgradeable`, `UUPSUpgradeable`
- Uses `initialize()` instead of constructor
- Constructor includes `_disableInitializers()` to prevent direct initialization
- Added `getVersion()` function for version tracking
- Added `_authorizeUpgrade()` for owner-only upgrades

### ReputationRegistryUpgradeable

- `identityRegistry` is stored in regular storage (not `immutable`)
- Takes `identityRegistry` address in `initialize(address)` instead of constructor
- Same functional behavior as original
- Added upgrade authorization and versioning

### ValidationRegistryUpgradeable

- `identityRegistry` is stored in regular storage (not `immutable`)
- Takes `identityRegistry` address in `initialize(address)` instead of constructor
- Same functional behavior as original
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
- Owner is set during initialization

### Storage Safety

- All contracts use OpenZeppelin's storage-safe upgradeable variants
- Storage slots are managed by OpenZeppelin to prevent conflicts
- Future upgrades must maintain storage layout of previous versions

### Immutable Variables

- Original contracts used `immutable` for `identityRegistry` (gas optimization)
- Upgradeable versions use regular storage (required for proxy pattern)
- Small gas cost increase but necessary for upgradeability

## Testing

`npm run test` will run both core and upgradeable test suites.

## Version Management

Each upgradeable contract includes a `getVersion()` function:

```solidity
function getVersion() external pure returns (string memory) {
    return "1.0.0";
}
```

When upgrading, increment this version number to track deployed versions.

## Gas Considerations

### Deployment

- Upgradeable contracts have slightly higher deployment costs due to:
  - Additional inherited contracts (Initializable, UUPSUpgradeable, etc.)
  - Proxy contract deployment
  - Extra storage for upgrade logic

### Runtime

- Minimal gas overhead for regular operations
- Proxy adds a single delegatecall per transaction (~700 gas)
- Storage access costs slightly higher for non-immutable identityRegistry

### Upgrade Costs

- New implementation deployment
- `upgradeToAndCall()` transaction
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

   - Never remove or reorder existing storage variables
   - Only add new storage variables at the end
   - Use storage gaps for future extensibility

4. **Version your implementations**
   - Update `getVersion()` for each new implementation
   - Keep track of which versions are deployed where
   - Document breaking changes

### For Operators

1. **Backup before upgrades**

   - Export critical data before upgrading
   - Have rollback plan ready
   - Test upgrade on fork first

2. **Secure owner keys**

   - Owner can upgrade contracts
   - Use multi-sig or timelock for production
   - Consider transferring ownership to governance

3. **Monitor after upgrades**
   - Verify version changed correctly
   - Check that all functions still work
   - Monitor for unexpected behavior

## Migration from Original Contracts

If you have existing non-upgradeable contracts deployed:

1. **Cannot upgrade existing deployments**

   - Original contracts don't have proxy pattern
   - Must deploy new upgradeable versions

2. **Data migration options**

   - Export data from old contracts
   - Recreate state in new contracts
   - Consider keeping old contracts for historical data

3. **Communication**
   - Inform users of new addresses
   - Update documentation
   - Redirect traffic to new deployments

## Resources

- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/5.x/upgradeable)
- [UUPS Proxy Pattern](https://eips.ethereum.org/EIPS/eip-1822)
- [EIP-1967 Proxy Storage Slots](https://eips.ethereum.org/EIPS/eip-1967)
- [Hardhat Ignition](https://hardhat.org/ignition)

## Support

For issues or questions:

- Check existing tests for usage examples
- Review OpenZeppelin upgradeable documentation
- Test on local network or testnet first
- Contact the development team

## License

CC0 - Public Domain (same as ERC-8004)
