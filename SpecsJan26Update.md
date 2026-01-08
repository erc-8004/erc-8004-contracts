# ERC-8004 Jan 2026 Spec Update

This document summarizes **all spec changes** incorporating community feedback gathered during the testnet phase (thanks everybody for your feedback!):

- **Old** (Oct 9): `https://raw.githubusercontent.com/ethereum/ERCs/cb7ae28320f7ef6f8794a17b031e874689757943/ERCS/erc-8004.md`
- **New** (Jan 9): `https://raw.githubusercontent.com/ethereum/ERCs/e8e4955370cef3a8039a7572b2149f1d8c276c8a/ERCS/erc-8004.md`

---

## Most important changes (read this first)

### 1) **Reputation feedback no longer requires agent-signed pre-authorization (`feedbackAuth`)**

**What changed**

- The old spec described a flow where **the agent signs a `feedbackAuth`** authorizing a given `clientAddress` to submit feedback (with index limits + expiry).
- The new spec removes `feedbackAuth` entirely and makes feedback submission a direct call by any `clientAddress`:
  - `giveFeedback(...)` no longer includes `feedbackAuth`.
  - The off-chain feedback JSON no longer includes a required `feedbackAuth` field.

**Why it matters**

- This is the biggest functional/trust-model change in the update: it removes pre-authorization friction for clients/reviewers submitting feedback, and it changes how spam resistance / client gating is achieved.
- The new spec leans harder on **filtering by reviewer/clientAddress** and off-chain aggregation for Sybil/spam mitigation (and references frictionless feedback via EIP-7702 in Rationale).

**Concrete interface impact**

- Old:
  - `giveFeedback(uint256 agentId, uint8 score, bytes32 tag1, bytes32 tag2, string fileuri, bytes32 filehash, bytes feedbackAuth)`
- New:
  - `giveFeedback(uint256 agentId, uint8 score, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)`

---

### 2) **Agent “wallet address” handling moves from off-chain endpoint-style fields to a reserved on-chain metadata key with signature verification**

**What changed**

- The example registration JSON removed the `agentWallet` entry from `endpoints`.
- The new spec defines a reserved metadata key **`agentWallet`** with special rules:
  - **Cannot** be set via `setMetadata()` nor during `register()`.
  - Initially set to the owner’s address.
  - Can be updated only by proving control of the new wallet via:
    - **EIP-712 signature** for EOAs, or
    - **ERC-1271** for smart-contract wallets.
  - On transfer, `agentWallet` is reset to the zero address and must be re-verified by the new owner.

**Why it matters**

- This makes “where the agent receives payments” a first-class, on-chain-verifiable attribute (rather than a best-effort off-chain declaration).

---

## Identity Registry changes (detailed)

### Agent identity primitives

- **New**: `agentRegistry` is formally introduced as `{namespace}:{chainId}:{identityRegistry}` with explanatory sub-bullets.
- **Clarified**: throughout the document, ERC-721 `tokenId` is `agentId` **and** ERC-721 `tokenURI` is `agentURI`.

### Agent URI / registration file rules

- **Renamed**: “Token URI” section becomes “Agent URI”.
- **Update mechanism changed**:
  - Old referenced updating registration via ERC721URIStorage internals (e.g., `_setTokenURI()`).
  - New adds **spec-level** `setAgentURI(...)` and `URIUpdated(...)`.
- **On-chain registration JSON**: if the owner wants to store the entire registration file on-chain, the `agentURI` SHOULD use a base64-encoded data URI rather than a serialized JSON string (e.g., `data:application/json;base64,eyJ0eXBlIjoi...`).

### Registration JSON schema (example) updates

The example registration JSON changed in several ways:

- **Added**: `web` and `email` endpoint examples as human-facing endpoints (reflecting community feedback that many agents provide a UI for humans, not just machine-to-machine endpoints).
- **Changed**: MCP `capabilities` example from `{}` to `[]`.
- **Upgraded**: OASF endpoint version from `0.7` to `0.8` and added optional `skills` and `domains` arrays.
- **Added**:
  - `x402Support: false`
  - `active: true`
- **Clarified**: `registrations[].agentRegistry` is shown as `{namespace}:{chainId}:{identityRegistry}` with an explicit example comment.

### Optional: Endpoint Domain Verification

**New optional verification mechanism**:

- Agents may prove control of an HTTPS endpoint-domain by hosting:
  - `https://{endpoint-domain}/.well-known/agent-registration.json`
- Verifiers may treat a domain as verified if that file contains a matching `registrations` entry (`agentRegistry` + `agentId`).
- If the endpoint domain is the same domain serving the primary `agentURI`, the extra check is not needed (domain control is already implied).

### Registration function signatures

The register functions were adjusted:

- **Renamed parameter**: `tokenURI` → `agentURI`

The `Registered` event now emits `agentURI` instead of `tokenURI`.

---

## Reputation Registry changes (detailed)

### Feedback payload model changes

**Feedback fields are redefined**:

- **New optional field**: `endpoint` URI is part of on-chain feedback submission.
- **Renamed**:
  - `fileuri` → `feedbackURI`
  - `filehash` → `feedbackHash`
- **Types changed**:
  - `tag1`, `tag2`: `bytes32` → `string` (including in read/filter functions)

### `giveFeedback` API changes

As covered in the “Most important changes” section:

- **Removed**: `feedbackAuth` requirement and the entire pre-authorization explanation (indexLimit/expiry/chainId/identityRegistry/signerAddress tuple).
- **Added**: `endpoint` parameter.
- **Clarified**: `tag1`, `tag2`, `endpoint`, `feedbackURI`, `feedbackHash` are OPTIONAL (only `agentId` and a 0–100 `score` are required).

### `NewFeedback` event changes

Event expanded:

- **Added**: `feedbackIndex` (per clientAddress per agentId)
- **Tags**: now `string`, and `tag1` remains indexed (as a `string`)
- **New fields**: `endpoint`, `feedbackURI`, `feedbackHash`

### Storage vs off-chain payload clarification

- New spec states that feedback fields **except** `feedbackURI` and `feedbackHash` are stored on-chain, while those two remain off-chain references/commitments.


### Responses appended to feedback

- Renamed `responseUri` → `responseURI`.
- Clarified that `responseHash` is **not required** for IPFS URIs (wording tightened vs “OPTIONAL”).

### Read/aggregation API changes

Key changes in read functions:

- `getSummary(...)` now uses `string tag1, string tag2` and retains optional filtering by `clientAddresses`.
- `readFeedback(...)`:
  - renames the parameter `index` → `feedbackIndex`
  - returns `string tag1, string tag2` instead of `bytes32`
- `readAllFeedback(...)`:
  - returns an additional `uint64[] feedbackIndexes`
  - returns `string[] tag1s/tag2s` instead of `bytes32[]`
  - clarifies that revoked feedback are **omitted by default** (controlled by `includeRevoked`)

### Off-chain feedback JSON example changes

The off-chain feedback file example was updated:

- **Removed required field**: `feedbackAuth`
- **Renamed**: `proof_of_payment` → `proofOfPayment`
- **Added optional fields**:
  - `endpoint`
  - `domain` (as-defined-by-OASF)
- **Broadened**: `skill` is now “as-defined-by-A2A-or-OASF”
- **Example cleanup**: placeholder strings normalized (e.g., `name: "foo"`).

---

## Validation Registry changes (detailed)

> **Warning**
>
> The **Validation Registry** portion of the ERC-8004 spec is **still under active update and discussion with the TEE community**. This section will be revised and expanded in a follow-up spec update **later this year**.

