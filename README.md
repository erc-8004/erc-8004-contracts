# ERC-8004: Trustless Agents

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

### Contract Addresses

#### Ethereum Mainnet
- **IdentityRegistry**: [`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`](https://etherscan.io/address/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432)
- **ReputationRegistry**: [`0x8004BAa17C55a88189AE136b182e5fdA19dE9b63`](https://etherscan.io/address/0x8004BAa17C55a88189AE136b182e5fdA19dE9b63)


#### Ethereum Sepolia
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


## About

This repository implements **ERC-8004 (Trustless Agents)**: a lightweight set of on-chain registries that make agents discoverable and enable trust signals across organizational boundaries.

At a high level, ERC-8004 defines three registries:

- **Identity Registry**: an ERC-721 registry for agent identities (portable, browsable, transferable).
- **Reputation Registry**: a standardized interface for publishing and reading feedback signals.
- **Validation Registry**: hooks for validator smart contracts to publish validation results.

The normative spec lives in `ERC8004SPEC.md`.

## Quickstart

Install dependencies:

```shell
npm install
```

Run tests:

```shell
npm test
```

Or via Hardhat:

```shell
npx hardhat test
```

## Core concepts (from the spec)

### Agent identifier

An agent is identified by:

- **agentRegistry**: `{namespace}:{chainId}:{identityRegistry}` (e.g., `eip155:11155111:0x...`)
- **agentId**: the ERC-721 `tokenId` minted by the Identity Registry

Off-chain payloads (registration files, feedback files, evidence) should include both fields so they can be tied back to the on-chain agent.

### What ERC-8004 does (and doesn’t)

- **Discovery**: ERC-8004 makes agents discoverable via an ERC-721 identity whose `tokenURI` points to a registration file.
- **Trust signals**: ERC-8004 standardizes how reputation and validation signals are posted and queried on-chain.
- **Not payments**: payment rails are intentionally out-of-scope; the spec shows how payments *can* enrich feedback signals, but ERC-8004 does not mandate a payment system.

## Registries

### Identity Registry (agent discovery)

The Identity Registry is an upgradeable ERC-721 (`ERC721URIStorage`) where:

- **agentURI** (`tokenURI`) points to the agent registration file (e.g., `ipfs://...` or `https://...`).
- **register** mints a new agent NFT and assigns an `agentId`.
- **setAgentURI** updates the agent’s URI.

#### On-chain metadata

The registry also provides optional on-chain metadata:

- `getMetadata(agentId, metadataKey) -> bytes`
- `setMetadata(agentId, metadataKey, metadataValue)`

The reserved key **`agentWallet`** is managed specially:

- It is set automatically on registration (initially to the owner’s address).
- It can be updated only after proving control of the new wallet via `setAgentWallet(...)` (EIP-712 / ERC-1271).
- It is cleared on transfer so a new owner must re-verify.
- Helpers: `getAgentWallet(agentId)` and `unsetAgentWallet(agentId)`.

#### Agent registration file (recommended shape)

The `agentURI` should resolve to a JSON document that is friendly to NFT tooling (name/description/image) and also advertises agent endpoints. The spec’s registration file includes:

- `type`: schema identifier for the registration format
- `name`, `description`, `image`
- `services`: a list of endpoints (e.g., A2A agent card URL, MCP endpoint, OASF manifest, ENS name, email)
- `registrations`: a list of `{ agentRegistry, agentId }` references to bind the file back to on-chain identity
- `supportedTrust`: optional list such as `reputation`, `crypto-economic`, `tee-attestation`

#### Optional: endpoint domain verification

If an agent advertises an HTTPS endpoint, it can optionally prove domain control by hosting a well-known file (see `ERC8004SPEC.md`). Verifiers can use it to confirm that an endpoint domain is controlled by the same agent identity.

### Reputation Registry (trust signals)

The Reputation Registry stores and exposes feedback signals as a signed fixed-point number:

- `value`: `int128` (signed)
- `valueDecimals`: `uint8` (0–18)

Everything else is optional metadata (tags, endpoint URI, off-chain payload URI + hash).

#### Interpreting `value` + `valueDecimals`

Treat the pair as a signed decimal number:

- Example: `value=9977`, `valueDecimals=2` → `99.77`
- Example: `value=560`, `valueDecimals=0` → `560`

This allows a single on-chain schema to represent percentages, scores, timings, dollar amounts, etc. (the meaning is conveyed by `tag1`/`tag2` and/or the off-chain file).

#### Give feedback

`giveFeedback(...)` records feedback for an agent. The implementation prevents **self-feedback** from the agent owner or approved operators (checked via the Identity Registry).

#### Read + aggregate

Typical read paths:

- `readFeedback(agentId, clientAddress, feedbackIndex)`
- `readAllFeedback(agentId, clientAddresses, tag1, tag2, includeRevoked)`
- `getSummary(agentId, clientAddresses, tag1, tag2)` → returns `(count, summaryValue, summaryValueDecimals)`

Note: `getSummary` requires `clientAddresses` to be provided (non-empty) to reduce Sybil/spam risk.

#### Responses & revocation

- Clients can revoke their feedback: `revokeFeedback(agentId, feedbackIndex)`
- Anyone can append responses: `appendResponse(agentId, clientAddress, feedbackIndex, responseURI, responseHash)`

## Suggested end-to-end flow

1. **Register an agent** in the Identity Registry (`register(...)`) and get an `agentId`.
2. **Publish a registration file** (e.g., on IPFS/HTTPS) and set it as the `agentURI` via `setAgentURI(agentId, ...)`.
3. (Optional) **Set a verified receiving wallet** via `setAgentWallet(...)` (EIP-712/1271 proof).
4. **Collect feedback** from users/clients via `giveFeedback(...)` on the Reputation Registry.
5. **Aggregate trust** in-app using `getSummary(...)` and/or pull raw feedback via `readAllFeedback(...)` for off-chain scoring.

### Validation Registry

> **Warning**
>
> The **Validation Registry** portion of the ERC-8004 spec is **still under active update and discussion with the TEE community**. This section will be revised and expanded in a follow-up spec update **later this year**.

The current implementation supports:

- `validationRequest(validatorAddress, agentId, requestURI, requestHash)` (must be called by owner/operator of `agentId`)
- `validationResponse(requestHash, response, responseURI, responseHash, tag)` (must be called by the requested validator)
- Read functions: `getValidationStatus`, `getSummary`, `getAgentValidations`, `getValidatorRequests`

## JSON payloads (off-chain)

### Agent registration file (Identity Registry)

The agent’s `agentURI` should resolve to a registration file (see `ERC8004SPEC.md`) containing human-friendly metadata plus a list of advertised services/endpoints (e.g., A2A, MCP, OASF, ENS, email).

### Feedback file (optional, Reputation Registry)

The on-chain feedback can optionally reference a richer off-chain JSON payload (again see the spec) that includes:

- `agentRegistry`, `agentId`, `clientAddress`, `createdAt`
- `value`, `valueDecimals`
- Optional categorization under namespaces like `mcp`, `a2a`, and `oasf`

Tip: keep the on-chain call minimal (tags + numeric signal), and put verbose context (task transcript, payment proof, artifacts, model/version info) in the off-chain JSON referenced by `feedbackURI`.

## Project structure

```
contracts/
├── IdentityRegistryUpgradeable.sol     - ERC-721 based agent registration (upgradeable)
├── ReputationRegistryUpgradeable.sol   - Feedback + aggregation (upgradeable)
└── ValidationRegistryUpgradeable.sol   - Validation request/response (upgradeable)

abis/                                  - Contract ABIs for integrations
ignition/modules/                       - Deployment modules
scripts/                                - Deployment/upgrade utilities
test/                                   - Test suite
ERC8004SPEC.md                           - Protocol spec used as source-of-truth for docs
```

## Resources

- [ERC-8004 Full Specification](./ERC8004SPEC.md)
- [ERC-8004 Website](https://www.8004.org)
- [Hardhat Documentation](https://hardhat.org/docs)
- [EIP-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)

## License

CC0 - Public Domain

## Contacts

ERC-8004 is a community effort coordinated by Marco De Rossi (MetaMask) and Davide Crapis (EF), with the co-authorship of Jordan Ellis (Google) and Erik Reppel (Coinbase). Our core team is joined by Leonard Tan (MetaMask), Vitto Rivabella (EF), and Isha Sangani (EF).

Check out our website at [8004.org](https://www.8004.org) and reach out at `team@8004.org`.
