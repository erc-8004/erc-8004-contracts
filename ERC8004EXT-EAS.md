# ERC-8004 Extension: Ethereum Attestation Service Integration

**Extension for attestation-based trust using EAS**

## Abstract

This extension integrates Ethereum Attestation Service (EAS) into ERC-8004 to provide a standardized, composable trust layer for agents. It defines:

1. **AgentURI → DID Address mapping** - Deterministic address derivation for EAS recipient indexing
2. **Trust model integration** - How attestations complement the base ERC-8004 Reputation Registry

This extension enables permissionless, multi-party attestations while maintaining compatibility with existing EAS infrastructure and tooling.

## Motivation

The base ERC-8004 Reputation Registry provides on-chain feedback storage for agents. This extension integrates Ethereum Attestation Service (EAS) to *extend* that foundation with additional capabilities:

- **Standardized discovery & indexing**: EAS is deployed across multiple chains with well-known contract addresses and established indexing tooling, making it easier for clients to discover and query trust signals consistently.
- **Greater expressiveness**: EAS supports an open-ended set of schemas, allowing different kinds of attestations (endorsements, certifications, audits, reviews, validations) without requiring a single fixed registry schema.
- **Clearer semantics**: Schema UIDs and typed fields make the meaning of a trust signal explicit and machine-readable, improving interoperability across clients.
- **Reuse of existing infrastructure**: EAS enables ERC-8004 deployments to leverage existing ecosystem contracts, explorers, and indexers rather than requiring separate bespoke infrastructure for each trust model.

This extension is intentionally additive: it does not replace the Reputation Registry, and clients remain free to combine Reputation Registry feedback with EAS-based attestations according to their own trust policies.

## Definitions

The following terms are used throughout this specification:

| Term                     | Definition                                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Extension**            | This specification document.                                                                                                        |
| **Base Specification**   | The [base ERC-8004 specification document](https://github.com/erc-8004/erc-8004-contracts/blob/master/ERC8004SPEC.md).              |
| **EAS**                  | [Ethereum Attestation Service](https://attest.sh).                                                                                  |
| **Identity Registry**    | The ERC-721 contract that stores agent registrations as defined in the Base Specification.                                          |
| **Reputation Registry**  | The ERC-721 contract that stores agent feedback as defined in the Base Specification.                                               |
| **Agent**                | A software service registered in the Identity Registry.                                                                             |
| **Client**               | Software that queries the Extension to obtain information about an Agent. Examples include wallets, marketplaces, and other agents. |
| **DID**                  | Decentralized Identifier as defined by the [W3C specification](https://www.w3.org/TR/did-core/#terminology).                        |
| **canonicalDID**         | The normalized form of a DID string as defined in this Extension.                                                                   |
| **didHash**              | The Keccak-256 hash of a canonicalDID as defined in this Extension.                                                                 |
| **DID Address**          | A 20-byte value derived by truncating a didHash, for use as an EAS recipient. Defined in this Extension.                            |

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

## Attestation Querying

Clients retrieve attestations about a DID using this flow:

```javascript
// 1. Compute DID Address
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

Example query filters: recipient=<didAddress>, schema=<schemaUID>.”

**Verification Requirements:**

Clients MUST verify:
1. `recipient` equals `didAddress(did)`
2. `subject` in payload equals the `did` used to derive recipient
3. Attestation is not revoked
4. Attestation is not expired (if `expirationTime` is set)
5. Attester is trusted (per client's trust policy)


## Future Direction: EAS v2 Migration Path

The current v1 EAS Extension uses a DID address as the value of the subject field in order to remain compatible with the canonical EAS contract interface, which strictly defines subject as an address.

This approach allows ERC-8004 identity registries and DIDs to participate in the EAS ecosystem today, but it is a transitional mechanism, not a permanent design choice. The DID address format is only a proxy representation of a DID or registry identifier—it was never intended to be a spendable or externally owned account, and implementations MUST treat it as a non-transferable identifier rather than a wallet address.

In v2, the EAS extension will migrate away from this workaround toward a more flexible subject model that allows:

- Native support for non-address subject types such as bytes32 (DID hashes), string (canonicalized DIDs), or structured identifiers (e.g., CAIP-19 asset references).
- A unified attestation schema capable of expressing cross-chain and cross-namespace subjects.
- Optional backward compatibility for v1 DID address subjects through SDK-level resolution.

This evolution is not a competing alternative to v1, but a planned migration path. The v1 approach ensures interoperability with existing EAS deployments. The v2 framework defines the long-term direction for EAS-compatible attestations across heterogeneous identifiers, registries, and chains.

Implementations integrating this specification should plan to:

- Continue supporting DID address subjects for legacy attestations.
- Add support for resolving v2 subject types as they become available.
- Transition indexers and SDKs to a unified query layer that transparently handles both v1 and v2 attestations.

## Copyright

Copyright and related rights waived via CC0.
