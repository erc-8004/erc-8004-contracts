# ERC-8004: Trustless Agents

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

### Testnet Contract Addresses

**All addresses follow the canonical `0x8004` pattern:**

#### Sepolia
- Identity: [`0x8004a6090Cd10A7288092483047B097295Fb8847`](https://sepolia.etherscan.io/address/0x8004a6090Cd10A7288092483047B097295Fb8847)
- Reputation: [`0x8004B8FD1A363aa02fDC07635C0c5F94f6Af5B7E`](https://sepolia.etherscan.io/address/0x8004B8FD1A363aa02fDC07635C0c5F94f6Af5B7E)
- Validation: [`0x8004CB39f29c09145F24Ad9dDe2A108C1A2cdfC5`](https://sepolia.etherscan.io/address/0x8004CB39f29c09145F24Ad9dDe2A108C1A2cdfC5)

#### Base Sepolia
- Identity: [`0x8004AA63c570c570eBF15376c0dB199918BFe9Fb`](https://sepolia.basescan.org/address/0x8004AA63c570c570eBF15376c0dB199918BFe9Fb)
- Reputation: [`0x8004bd8daB57f14Ed299135749a5CB5c42d341BF`](https://sepolia.basescan.org/address/0x8004bd8daB57f14Ed299135749a5CB5c42d341BF)
- Validation: [`0x8004C269D0A5647E51E121FeB226200ECE932d55`](https://sepolia.basescan.org/address/0x8004C269D0A5647E51E121FeB226200ECE932d55)

#### Linea Sepolia
- Identity: [`0x8004aa7C931bCE1233973a0C6A667f73F66282e7`](https://sepolia.lineascan.build/address/0x8004aa7C931bCE1233973a0C6A667f73F66282e7)
- Reputation: [`0x8004bd8483b99310df121c46ED8858616b2Bba02`](https://sepolia.lineascan.build/address/0x8004bd8483b99310df121c46ED8858616b2Bba02)
- Validation: [`0x8004c44d1EFdd699B2A26e781eF7F77c56A9a4EB`](https://sepolia.lineascan.build/address/0x8004c44d1EFdd699B2A26e781eF7F77c56A9a4EB)

#### Hedera Testnet
- **IdentityRegistry**: `0x4c74ebd72921d537159ed2053f46c12a7d8e5923`
- **ReputationRegistry**: `0xc565edcba77e3abeade40bfd6cf6bf583b3293e0`
- **ValidationRegistry**: `0x18df085d85c586e9241e0cd121ca422f571c2da6`

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
├── IdentityRegistry.sol     - ERC-721 based agent registration
├── ReputationRegistry.sol   - Feedback and reputation tracking
└── ValidationRegistry.sol   - Validation request/response system

test/
└── ERC8004.ts              - Comprehensive test suite

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
- Agents request validation from specific validators
- Validators respond with 0-100 scores and optional tags
- Support for progressive validation states
- Track all validations per agent and per validator
- On-chain aggregation with filtering

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
