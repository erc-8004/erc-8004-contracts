# ERC-8004 Extension: Ethereum Attestation Service Integration

**Extension for attestation-based trust using EAS**

## Abstract

This extension integrates Ethereum Attestation Service (EAS) into ERC-8004 to provide a standardized, composable trust layer for agents. It defines:

1. **AgentURI → DID Address mapping** - Deterministic address derivation for EAS recipient indexing
2. **Off-chain attestation querying** - How off-chain clients discover and verify EAS attestations using DID Addresses
3. **On-chain attestation indexing** - How the Reputation Registry serves as an on-chain index into EAS, enabling smart contract verifiers to discover and retrieve attestations by agentId
4. **Trust model integration** - How attestations complement the base ERC-8004 Reputation Registry

This extension enables permissionless, multi-party attestations while maintaining compatibility with existing EAS infrastructure and tooling.

## Motivation

The base ERC-8004 Reputation Registry provides on-chain feedback storage for agents. This extension integrates Ethereum Attestation Service (EAS) to *extend* that foundation with additional capabilities:

- **Standardized discovery & indexing**: EAS is deployed across multiple chains with well-known contract addresses and established indexing tooling, making it easier for clients to discover and query trust signals consistently.
- **Greater expressiveness**: EAS supports an open-ended set of schemas, allowing different kinds of attestations (endorsements, certifications, audits, reviews, validations) without requiring a single fixed registry schema.
- **Clearer semantics**: Schema UIDs and typed fields make the meaning of a trust signal explicit and machine-readable, improving interoperability across clients.
- **Reuse of existing infrastructure**: EAS enables ERC-8004 deployments to leverage existing ecosystem contracts, explorers, and indexers rather than requiring separate bespoke infrastructure for each trust model.
- **On-chain composability**: By indexing EAS attestation references in the Reputation Registry, smart contracts can discover and retrieve attestations without relying on off-chain indexers.

This extension is intentionally additive: it does not replace the Reputation Registry, and clients remain free to combine Reputation Registry feedback with EAS-based attestations according to their own trust policies.

## Definitions

The following terms are used throughout this specification:

| Term                     | Definition                                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Extension**            | This specification document.                                                                                                        |
| **Base Specification**   | The [base ERC-8004 specification document](https://github.com/erc-8004/erc-8004-contracts/blob/master/ERC8004SPEC.md).              |
| **EAS**                  | [Ethereum Attestation Service](https://attest.sh).                                                                                  |
| **Identity Registry**    | The ERC-721 contract that stores agent registrations as defined in the Base Specification.                                          |
| **Reputation Registry**  | The contract that stores agent feedback as defined in the Base Specification.                                                        |
| **Agent**                | A software service registered in the Identity Registry.                                                                             |
| **Client**               | Software that queries the Extension to obtain information about an Agent. Examples include wallets, marketplaces, and other agents. |
| **DID**                  | Decentralized Identifier as defined by the [W3C specification](https://www.w3.org/TR/did-core/#terminology).                        |
| **canonicalDID**         | The normalized form of a DID string as defined in this Extension.                                                                   |
| **didHash**              | The Keccak-256 hash of a canonicalDID as defined in this Extension.                                                                 |
| **DID Address**          | An EAS recipient `bytes20` value derived by truncating a didHash. See *Output Encoding (Normative)* for serialization rules.        |

Terms defined in the Base Specification are incorporated by reference.

## Background

### What is a DID?

A Decentralized Identifier (DID) is a globally unique identifier that does not require a centralized registration authority. DIDs are defined by the [W3C DID Core specification](https://www.w3.org/TR/did-core/). A DID consists of three parts: the scheme (`did:`), a method identifier, and a method-specific identifier. For example, `did:web:example.com` uses the `web` method with `example.com` as the method-specific identifier.

This Extension uses the `did:web` method, which allows domain names and paths to be used as DIDs. The `did:web` method is specified in the [W3C DID Web Method specification](https://w3c-ccg.github.io/did-method-web/).

### What is Ethereum Attestation Service?

Ethereum Attestation Service (EAS) is an open-source, permissionless attestation infrastructure that enables anyone to make attestations on-chain or off-chain about anything. It was developed with support from the Ethereum Foundation and is maintained by a growing ecosystem of projects and developers.

**Key Resources:**

- **Website**: [https://attest.org](https://attest.org)
- **Documentation**: [https://docs.attest.org](https://docs.attest.org)
- **GitHub**: [https://github.com/ethereum-attestation-service](https://github.com/ethereum-attestation-service)
- **Explorer**: [https://easscan.org](https://easscan.org)
- **GraphQL Indexer**: [https://easscan.org/graphql](https://easscan.org/graphql)

**Deployment Status:**

The EAS team deployed EAS on multiple EVM-compatible chains including:

- Ethereum Mainnet
- Optimism
- Base
- Arbitrum
- Polygon
- Linea
- Scroll

EAS repositories are open-source, so many more unofficial deployments also exist. 

**Semantics of `recipient` in EAS**

In EAS, `recipient` represents the entity being attested to.  It is the same as "subject" in the DID specification.  EAS uses the Solidity type `address` for `recipient` as it is the only native identifier type in Solidity.  EAS uses the Solidity type address for recipient purely as a compact 20-byte identifier. The EAS protocol never interprets this as an executable account or owner. It is a data key, not a security principal. In practice, this means that the `recipient` value:

- MAY correspond to an externally owned account (EOA) or smart contract
- but also MAY represent a logical identity, such as a DID, an ERC-721 token, or another off-chain entity deterministically encoded into 20 bytes

This background is important when reading this specification. 

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### DID Address

In order to integrate EAS into ERC-8004, this Extension defines the formal use of the EAS `recipient` field as the generic identifier of a subject. This generic subject identifier uses a new logical identifier type: **DID Address**, a 20-byte value derived from a DID.  *agentURI* can be converted to a DID using the `did:web` method.

DID Address:
- Preserves determinism (same URI or DID always produces the same DID Address)
- Ensures collision resistance (≈ 1 / 2^160 probability)
- Fits naturally into EAS's existing `recipient` field size without requiring protocol changes

**URI to DID**

To convert a URL/URI to a `did:web` DID, the following algorithm MUST be used:

1. Parse the URL to extract the hostname and path components
2. The hostname MUST be converted to lowercase
3. Leading and trailing slashes MUST be removed from the path
4. Path separators (`/`) MUST be replaced with colons (`:`)
5. The resulting DID MUST have the format `did:web:<hostname>[:<path-segments>]`

**Conversion Examples:**

| URL | DID |
| --- | --- |
| `https://agent.example.com` | `did:web:agent.example.com` |
| `https://example.com/agents/myagent` | `did:web:example.com:agents:myagent` |
| `https://example.com/.well-known/agent.json` | `did:web:example.com:.well-known:agent.json` |

**DID Canonicalization**

To ensure deterministic hashing, DIDs MUST be canonicalized before hashing. The canonicalization algorithm for `did:web` is as follows:

1. The DID MUST start with the prefix `did:`
2. The DID MUST contain at least three colon-separated parts: `did`, method, and method-specific identifier
3. For `did:web`, the hostname portion MUST be converted to lowercase
4. Path segments (if present) MUST preserve their original case

**Canonicalization Examples:**

| Input DID | Canonical DID |
| --------- | ------------- |
| `did:web:Example.COM` | `did:web:example.com` |
| `did:web:Example.COM:Agents:MyAgent` | `did:web:example.com:Agents:MyAgent` |

**DID Hash (didHash)**

A `didHash` is a 32-byte value computed from a canonical DID. The computation algorithm MUST be performed as follows:

1. Canonicalize the DID using the algorithm defined above
2. Encode the canonical DID string as UTF-8 bytes
3. Compute the Keccak-256 hash of the UTF-8 bytes
4. The resulting 32-byte value is the `didHash`

**DID Address Computation**

A DID Address MUST be computed by truncating the didHash to 20 bytes. The computation algorithm is as follows:

1. Compute the `didHash` from the canonical DID using the algorithm defined above
2. Take the least significant 160 bits (last 20 bytes) of the didHash
3. The resulting 20-byte value is the DID Address

The DID Address can be used anywhere an `address` index is expected—EAS recipients, event partition keys, or contract mappings. Collision risk is negligible (≈ 1 / 2^160).

**Output Encoding (Normative)**

The DID Address is conceptually a 20-byte value (`bytes20`).

When serialized as a string, it MUST be:

- `0x`-prefixed
- lowercase
- exactly 40 hexadecimal characters

EIP-55 checksum casing MUST NOT be required.

**Solidity Example:**

```solidity
library DidIndex {
    /// @notice Compute the DID Address used for EAS recipient or other address-keyed indexes.
    /// @dev didHash = keccak256(abi.encodePacked(canonicalizeDID(did)))
    function toAddress(bytes32 didHash) internal pure returns (address) {
        return address(uint160(uint256(didHash)));
    }
}
```

**Reference Implementation:**

A complete TypeScript implementation is provided in [`scripts/did-utils.ts`](./scripts/did-utils.ts).

**Critical: DID Address is NOT a Wallet**

The DID Address derived from a DID:
- MUST NOT be interpreted as a signer or owner
- MUST NOT receive asset transfers (ETH, tokens, NFTs)
- MUST NOT be used for access control or permissions
- SHOULD only be used as an EAS `recipient` for indexing and querying

**Rationale**

This usage of the EAS `recipient` enables efficient DID discovery in EAS. As long as an agent has a URL (e.g.- agentUri), anyone can:

1. Convert the URL to a `did:web` DID
2. Compute the `didHash`
3. Derive the DID Address
4. Create or search for attestations using that address as the EAS `recipient`

## Schema Design

When creating attestation schemas for DIDs, implementations MUST include a `subject` field in the schema definition. The `subject` field:

- SHOULD use type `string` to store the full DID (e.g., `"did:web:example.com"`)
- MUST be the DID that was used to derive the `recipient` address

Why Both `recipient` and `subject`?

- **`recipient` (address)**: EAS indexing key - enables efficient queries by DID Address
- **`subject` (string)**: Verification field - proves attestation is about the correct DID

This dual-field approach prevents spoofing attacks where an attacker could create attestations with a valid `recipient` but different `subject` content.

## Standard Attestation Schemas

This extension defines standard schemas for agent trust attestations. All schemas include the required `subject` field for DID verification.  These will be listed here in a future version of the Extension.


## Off-Chain Attestation Discovery

This section describes how off-chain clients (wallets, marketplaces, agent orchestrators, and other software running outside the EVM) discover and verify EAS attestations for agents. Off-chain clients have access to EAS GraphQL indexers and RPC endpoints, so they can query attestations directly using the DID Address as the EAS `recipient`.

### Querying Flow

Clients retrieve attestations about a DID using this flow:

```javascript
// 1. Compute DID Address from the agent's URI or DID
const didAddress = didToAddress(did);

// 2. Query EAS for attestations
const attestations = await eas.getAttestations({
    recipient: didAddress,
    schemaUID: SCHEMA_UID_USER_REVIEW
});

// 3. Verify each attestation
for (const attestation of attestations) {
    const payload = decodeAttestationData(attestation.data);
    
    // MUST verify subject matches
    if (payload.subject !== did) {
        throw new Error("DID hash mismatch");
    }
    
    // Process valid attestation
    processAttestation(payload);
}
```

Clients MAY index EAS attestations by DID Address using subgraphs or EAS GraphQL endpoints.

Example query filters: `recipient=<didAddress>`, `schema=<schemaUID>`.

### Verification Requirements

Clients MUST verify:
1. `recipient` equals `didAddress(did)`
2. `subject` in payload equals the `did` used to derive recipient
3. Attestation is not revoked
4. Attestation is not expired (if `expirationTime` is set)
5. Attester is trusted (per client's trust policy)


## On-Chain Attestation Discovery

This section describes how on-chain clients (smart contract verifiers, automated agents, and other contracts) discover and retrieve EAS attestations for agents. Unlike off-chain clients, smart contracts cannot query EAS GraphQL indexers or RPC endpoints. They need a way to discover attestation UIDs from an `agentId` using only on-chain state.

The Reputation Registry's `giveFeedback()` function serves as this on-chain index. When an EAS attestation is created for an agent, the attestation creator (or any third party) also records a feedback entry in the Reputation Registry that references the attestation. This creates a fully on-chain discovery path from `agentId` to EAS attestation.

### Reputation Registry Field Conventions

The Reputation Registry's `tag1` and `tag2` fields are stored in contract storage and are readable by smart contracts via `readFeedback()` and `readAllFeedback()`. This extension defines the following conventions for EAS-indexed feedback entries:

**`tag1`: Reputation Framework Identifier**

`tag1` MUST be set to `"eas"` for feedback entries that reference EAS attestations.

`tag1` serves as a framework discriminator. It identifies the format and semantics of `tag2`. Other reputation frameworks MAY define their own `tag1` values (e.g., future frameworks could use different identifiers). The value of `tag1` tells the verifier how to interpret `tag2`.

**`tag2`: Attestation Reference**

`tag2` encodes the EAS attestation UID and, optionally, the chain and contract location of the attestation. The format is:

```
<uid>[:<chainId>[:<easContractAddress>]]
```

Where:
- `uid` (REQUIRED): The EAS attestation UID, a `bytes32` value encoded as a `0x`-prefixed, lowercase hex string (66 characters).
- `chainId` (OPTIONAL): The EVM chain ID where the attestation exists, as a decimal string (e.g., `1` for Ethereum mainnet). If omitted, the attestation is assumed to be on the same chain as the Reputation Registry.
- `easContractAddress` (OPTIONAL): The address of the EAS contract, as a `0x`-prefixed, lowercase hex string (42 characters). If omitted, the well-known official EAS contract address for the specified chain MUST be used. This field is only needed for unofficial or custom EAS deployments.

`chainId` MUST be present if `easContractAddress` is present.

**`tag2` Examples:**

| Scenario                                    | `tag2` value                          |
| ------------------------------------------- | ------------------------------------- |
| Same chain, official EAS                    | `0xabc123...def`                      |
| Different chain (Base), official EAS        | `0xabc123...def:8453`                 |
| Different chain, unofficial EAS deployment  | `0xabc123...def:8453:0x5678...ef01`   |

> **Note on CAIP-10 compatibility:** A future revision of this extension MAY adopt a CAIP-10-aligned format by prepending the `eip155:` namespace prefix before the chain ID (e.g., `0xabc123...def:eip155:8453:0x5678...ef01`). The current format omits the namespace prefix because EAS is exclusively an EVM technology, making the prefix redundant. However, there are advantages to including the namespace prefix as it would make the fields after `uid` CAIP-10 compliant.

> **Note on gas efficiency:** The current `tag2` encoding uses a human-readable string format, which is convenient for off-chain tooling but not gas-efficient for on-chain parsing. A future revision MAY adopt a more compact encoding (e.g., ABI-encoded `bytes` or a packed binary format) to reduce storage and parsing costs for on-chain verifiers.

### Recording an EAS Attestation in the Reputation Registry

When an EAS attestation is created for an agent, the attestation creator (or any party) SHOULD also call `giveFeedback()` on the Reputation Registry to index the attestation on-chain:

```solidity
reputationRegistry.giveFeedback(
    agentId,                    // The agent's Identity Registry token ID
    value,                      // Feedback value (e.g., rating from the attestation)
    valueDecimals,              // Decimal precision of the value
    "eas",                      // tag1: framework identifier
    tag2,                       // tag2: "<uid>" or "<uid>:<chainId>" or "<uid>:<chainId>:<contractAddress>"
    endpoint,                   // OPTIONAL: agent endpoint reviewed (emitted, not stored)
    feedbackURI,                // OPTIONAL: URI to off-chain feedback file (emitted, not stored)
    feedbackHash                // OPTIONAL: hash of feedbackURI content (emitted, not stored)
);
```

The `value` and `valueDecimals` fields SHOULD reflect the attestation's primary signal (e.g., a rating value from a user review schema). This ensures that `getSummary()` can aggregate EAS-backed feedback alongside native Reputation Registry feedback.

### On-Chain Verification Flow

A verifier contract can discover and retrieve EAS attestations for an agent using the following pattern:

```solidity
// Step 1: Verify registry linkage
require(
    reputationRegistry.getIdentityRegistry() == expectedIdentityRegistry,
    "Registry mismatch"
);

// Step 2: Read EAS-tagged feedback entries
(
    address[] memory clients,
    uint64[] memory feedbackIndexes,
    int128[] memory values,
    uint8[] memory valueDecimals,
    string[] memory tag1s,
    string[] memory tag2s,
    bool[] memory revokedStatuses
) = reputationRegistry.readAllFeedback(
    agentId,
    trustedReviewers,   // Filter to trusted reviewer addresses
    "eas",              // tag1 filter: only EAS-backed entries
    "",                 // tag2 filter: empty = no additional filtering
    false               // exclude revoked
);

// Step 3: Derive the expected DID Address from the agent's URI
string memory agentURI = identityRegistry.tokenURI(agentId);
address expectedDIDAddress = EASIndex.uriToDIDAddress(agentURI);

// Step 4: For each entry, parse tag2 and retrieve the attestation
for (uint256 i = 0; i < clients.length; i++) {
    EASIndex.AttestationRef memory ref = EASIndex.parseTag2(tag2s[i]);
    
    // Skip cross-chain attestations (cannot verify on-chain)
    if (ref.chainId != 0 && ref.chainId != block.chainid) continue;
    
    // Retrieve the attestation from EAS
    Attestation memory attestation = eas.getAttestation(ref.uid);
    
    // Skip revoked attestations
    if (attestation.revocationTime != 0) continue;
    
    // Verify the attestation's recipient matches the agent's DID Address
    if (attestation.recipient != expectedDIDAddress) continue;
    
    // Schema-specific verification
    // (e.g., check expiration, decode rating, verify proof of payment, etc.)
    // ...
}
```

### EAS Index Library Interface

This extension defines a Solidity library interface for parsing `tag2` and resolving EAS attestations. The implementation is deferred to a future version of this extension.

```solidity
/// @title EASIndex
/// @notice Library for parsing Reputation Registry tag2 values that reference EAS attestations.
library EASIndex {

    struct AttestationRef {
        bytes32 uid;              // EAS attestation UID
        uint256 chainId;          // 0 = same chain as Reputation Registry
        address easContract;      // address(0) = use well-known EAS contract
    }

    /// @notice Parse a tag2 string into its component parts.
    /// @param tag2 The tag2 value from a Reputation Registry feedback entry where tag1 = "eas".
    /// @return ref The parsed attestation reference.
    function parseTag2(string memory tag2) internal pure returns (AttestationRef memory ref);

    /// @notice Retrieve an EAS attestation from a parsed reference.
    /// @dev Only works for same-chain attestations. Reverts if chainId != 0 and does not match block.chainid.
    /// @param ref The parsed attestation reference.
    /// @return attestation The full EAS Attestation struct.
    function getAttestation(AttestationRef memory ref) internal view returns (Attestation memory attestation);

    /// @notice Convert an HTTPS URI (e.g., agentURI) to a DID Address.
    /// @dev Converts URI to did:web, canonicalizes, computes keccak256, and truncates to 20 bytes.
    ///      Example: "https://agent.example.com/v1/chat" -> 0x...
    /// @param uri The HTTPS URI to convert.
    /// @return didAddress The 20-byte DID Address derived from the URI.
    function uriToDIDAddress(string memory uri) internal pure returns (address didAddress);
}
```

### Cross-Chain Limitations

On-chain attestation retrieval via `EASIndex.getAttestation()` is only possible when the attestation resides on the same chain as the Reputation Registry. If `tag2` specifies a different `chainId`, the on-chain verifier cannot directly retrieve the attestation.

For cross-chain scenarios, verifiers MUST either:
- Trust the Reputation Registry feedback entry as a proxy signal (the `value` and `valueDecimals` fields reflect the attestation's content)
- Use an off-chain relay or oracle to verify the attestation on the remote chain
- Require attestations to be created on the same chain as the Reputation Registry

## Copyright

Copyright and related rights waived via CC0.
