# Verified Agent Wallet (ERC-8004)

This document describes how ERC-8004 agents can publish an **agent wallet address** in a way that is **cryptographically verified** on-chain.

## Why this exists

Agents often want to associate an on-chain wallet (e.g. for payments, attestations, agent actions) with their ERC-8004 identity (`agentId`). If the wallet is set as “plain metadata”, anyone who controls the agent NFT (or is approved) could point it to **any** address without proving control of that wallet.

This change enforces: **the new wallet must prove ownership by signature**.

## High-level approach

We introduce a dedicated function that sets the agent wallet only when:

- The caller is **authorized** for the agent NFT (`ownerOf` / `isApprovedForAll` / `getApproved`)
- The **new wallet** signs an EIP-712 message authorizing the link
- The signature is valid for:
  - EOAs via ECDSA recovery
  - Contract wallets via **ERC-1271**
- The signature includes a `deadline` and the contract enforces:
  - `block.timestamp <= deadline`
  - `deadline <= block.timestamp + 5 minutes`

### No nonce

This scheme intentionally uses **no nonce**. As a tradeoff, the same signature can be replayed until `deadline`. The **maximum replay/rollback window is bounded to 5 minutes** by contract policy.

## Where the value is stored

The wallet is stored in the identity registry as **reserved string metadata** under the key:

- **Key**: `"agentWallet"`
- **Value**: a canonical 0x-prefixed 20-byte hex address string (e.g. `0xabc...`)

To prevent bypassing the signature gate:

- `setMetadata(agentId, "agentWallet", ...)` is blocked (reserved key)
- `register(..., metadata)` cannot include `"agentWallet"` either
- Only `setAgentWallet(...)` can set the wallet value

The canonical read methods for consumers are:

- `getAgentWallet(agentId) -> address` (address-typed convenience)
- `getMetadata(agentId, "agentWallet") -> string` (canonical string form)

## On-chain API

### Setting a verified agent wallet

`setAgentWallet(agentId, newWallet, deadline, signature)`

- **Caller**: agent NFT owner / approved
- **Signer**: `newWallet` (EOA or ERC-1271 contract)

### Reading

- `getAgentWallet(agentId) -> address`
- `getMetadata(agentId, "agentWallet") -> string`

## EIP-712 signature format

### Domain

- `name`: `ERC8004IdentityRegistry`
- `version`: `1`
- `chainId`: current chain id
- `verifyingContract`: the identity registry proxy address

### Primary type

`AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)`

Message fields:
- `agentId`: the agent NFT id
- `newWallet`: wallet being linked
- `owner`: **current** `ownerOf(agentId)` at verification time
- `deadline`: unix timestamp

## Operational recommendations

- Use very short deadlines (the contract enforces **max +5 minutes**).
- Treat signatures as bearer tokens until expiry: anyone who obtains the signature can submit it.


