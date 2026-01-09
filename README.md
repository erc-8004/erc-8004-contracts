# ERC-8004: Trustless Agents

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

### Contract Addresses (Jan 2026 Test Net)

#### ETH Sepolia
- **IdentityRegistry**: [`0x8004A818BFB912233c491871b3d84c89A494BD9e`](https://sepolia.etherscan.io/address/0x8004A818BFB912233c491871b3d84c89A494BD9e)
- **ReputationRegistry**: [`0x8004B663056A597Dffe9eCcC1965A193B7388713`](https://sepolia.etherscan.io/address/0x8004B663056A597Dffe9eCcC1965A193B7388713)

#### Base Sepolia
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### Linea Sepolia
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### Polygon Amoy
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### Hedera Testnet
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### HyperEVM Testnet
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### SKALE Base Sepolia Testnet
- **IdentityRegistry**: to be deployed
- **ReputationRegistry**: to be deployed

#### 0G Galileo Testnet
- **IdentityRegistry**: [`0x80043ed9cf33a3472768dcd53175bb44e03a1e4a`](https://chainscan-galileo.0g.ai/address/0x80043ed9cf33a3472768dcd53175bb44e03a1e4a)
- **ReputationRegistry**: [`0x80045d7b72c47bf5ff73737b780cb1a5ba8ee202`](https://chainscan-galileo.0g.ai/address/0x80045d7b72c47bf5ff73737b780cb1a5ba8ee202)
- **ValidationRegistry**: [`0x80041728e0aadf1d1427f9be18d52b7f3afefafb`](https://chainscan-galileo.0g.ai/address/0x80041728e0aadf1d1427f9be18d52b7f3afefafb)

## About

This project implements **ERC-8004**, a protocol that enables discovering, choosing, and interacting with agents across organizational boundaries without pre-existing trust. It provides three core registries:

- **Identity Registry**: A minimal on-chain handle based on ERC-721 with URIStorage extension that gives every agent a portable, censorship-resistant identifier
- **Reputation Registry**: A standard interface for posting and fetching feedback signals, enabling composable reputation systems
- **Validation Registry**: Generic hooks for requesting and recording independent validator checks (e.g., stakers re-running jobs, zkML verifiers, TEE oracles)

## Project Structure

```
contracts/
├── IdentityRegistryUpgradeable.sol     - ERC-721 based agent registration (upgradeable)
├── ReputationRegistryUpgradeable.sol   - Feedback and reputation tracking (upgradeable)
└── ValidationRegistryUpgradeable.sol   - Validation request/response system (upgradeable)

test/
├── core.ts                 - Core behavior tests
├── upgradeable.ts          - Upgradeability / proxy tests
└── local.ts                - Local network workflow tests

ERC8004SPEC.md              - Full protocol specification
```

## Key Features

### Identity Registry
- ERC-721 NFT-based agent registration with auto-incrementing agent IDs
- Token URI points to agent registration file (IPFS, HTTPS, etc.)
- On-chain metadata storage for key-value pairs (e.g., agentWallet, agentName)
- Support for metadata during registration

### Reputation Registry
- Clients can give feedback (0-100 score) with optional tags and off-chain file references
- Pre-authorization via cryptographic signatures (`feedbackAuth`)
- Support for feedback revocation and responses
- On-chain aggregation (count, average score) with filtering by client addresses and tags
- Multiple feedback entries per client-agent pair

### Validation Registry
> **Warning**
>
> The **Validation Registry** portion of the ERC-8004 spec is **still under active update and discussion with the TEE community**. This section will be revised and expanded in a follow-up spec update **later this year**.

## Installation

```shell
npm install
```

## Running Tests

Run all tests:
```shell
npm test
```

Or using Hardhat directly:
```shell
npx hardhat test
```

The test suite includes comprehensive coverage of:
- Agent registration and metadata management
- Feedback submission, revocation, and responses
- FeedbackAuth signature verification (EIP-191)
- Validation requests and responses
- Permission controls and access restrictions
- Summary calculations with filtering
- Edge cases and error conditions

## Development

This project uses:
- **Hardhat 3** with native Node.js test runner (`node:test`)
- **Viem** for Ethereum interactions
- **TypeScript** for type safety
- **OpenZeppelin Contracts** for ERC-721 implementation

## Protocol Overview

### Agent Registration
Each agent is uniquely identified by:
- `namespace`: eip155 (for EVM chains)
- `chainId`: The blockchain network identifier
- `identityRegistry`: The registry contract address
- `agentId`: The ERC-721 token ID

### Trust Models
ERC-8004 supports three pluggable trust models:
1. **Reputation**: Client feedback and scoring
2. **Validation**: Stake-secured re-execution, zkML proofs, or TEE oracles
3. **TEE Attestation**: Trusted Execution Environment verification

### Security Considerations
- Pre-authorization mitigates unauthorized feedback but doesn't prevent Sybil attacks
- On-chain pointers and hashes ensure immutable audit trails
- Validator incentives and slashing managed by specific validation protocols
- Reputation aggregation expected to evolve with off-chain services

## Resources

- [ERC-8004 Full Specification](./ERC8004SPEC.md)
- [Hardhat Documentation](https://hardhat.org/docs)
- [EIP-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)

## License

CC0 - Public Domain
