# Registry Address Discovery

`registry-addresses.json` is the canonical bootstrap map for registry contract addresses across chains.

It is keyed by CAIP-2 chain identifiers:

- EVM: `eip155:{chainId}` (for example `eip155:1`, `eip155:8453`)
- Starknet (draft namespace): `starknet:SN_MAIN`, `starknet:SN_SEPOLIA`

## Why this file exists

On EVM chains, deterministic CREATE2 deployment can keep addresses identical across many networks.
On non-EVM chains (for example Starknet), address derivation is different, so identical addresses are not always possible.

Scanners, watchtowers, and indexers still need one canonical place to resolve:

1. which registry to query for a chain
2. which address is currently canonical for that chain

## How to use it

1. Resolve the chain key (CAIP-2).
2. Read the registry address under `identity`, `reputation`, or `validation`.
3. If a value is `"<pending_review>"`, treat that network as not finalized.

## Update policy

- Update this file via PR whenever a registry deployment changes.
- Keep addresses checksummed for EVM entries.
- Additive updates are preferred (append new chains, avoid breaking keys).

## Extensibility

This format is chain-agnostic by design. Additional non-EVM namespaces can be added later (for example Sui, Solana, Aptos) without changing scanner logic.
