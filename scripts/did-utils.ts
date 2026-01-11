/**
 * DID Address Utilities
 * 
 * Implements the ERC-8004 EAS Extension specification for converting DIDs
 * to deterministic Ethereum addresses for EAS recipient indexing.
 * 
 * Transformation chain: URL → DID → canonicalDID → didHash → DID Address
 */

import { keccak256, toBytes, getAddress, type Address } from 'viem'

/**
 * Convert a URL to a did:web DID
 * @param url - The URL to convert
 * @returns DID in did:web format
 */
export function urlToDid(url: string): string {
  const urlObj = new URL(url)
  const host = urlObj.hostname.toLowerCase()
  const path = urlObj.pathname.replace(/^\//, '').replace(/\/$/, '')

  if (path) {
    return `did:web:${host}:${path.replace(/\//g, ':')}`
  }
  return `did:web:${host}`
}

/**
 * Canonicalize a DID according to its method specification
 * @param did - The DID string to canonicalize
 * @returns Canonicalized DID string
 */
export function canonicalizeDID(did: string): string {
  if (!did.startsWith('did:')) {
    throw new Error('Invalid DID format: must start with "did:"')
  }

  const parts = did.split(':')
  if (parts.length < 3) {
    throw new Error('Invalid DID format: insufficient parts')
  }

  const method = parts[1]

  switch (method) {
    case 'web': {
      // For did:web, lowercase the host and preserve the path
      const methodSpecificId = parts.slice(2).join(':')
      const colonIndex = methodSpecificId.indexOf(':')

      if (colonIndex === -1) {
        // No path segments, just hostname
        return `did:web:${methodSpecificId.toLowerCase()}`
      }

      const host = methodSpecificId.substring(0, colonIndex).toLowerCase()
      const pathSegments = methodSpecificId.substring(colonIndex + 1)

      return `did:web:${host}:${pathSegments}`
    }

    case 'pkh': {
      // For did:pkh, use canonical CAIP-10 encoding (lowercase address)
      if (parts.length !== 5) {
        throw new Error('Invalid did:pkh format: must have 5 parts')
      }
      const [, , namespace, chainId, address] = parts
      return `did:pkh:${namespace}:${chainId}:${address.toLowerCase()}`
    }

    default:
      // For other methods, lowercase the entire DID
      return did.toLowerCase()
  }
}

/**
 * Compute the DID hash using keccak256
 * @param did - The DID string (will be canonicalized)
 * @returns 32-byte hash as hex string
 */
export function computeDidHash(did: string): `0x${string}` {
  const canonicalDid = canonicalizeDID(did)
  return keccak256(toBytes(canonicalDid))
}

/**
 * Compute the DID Address by truncating didHash to 20 bytes
 * @param didHash - The keccak256 hash of the canonicalized DID
 * @returns Checksummed Ethereum address
 */
export function computeDidAddress(didHash: `0x${string}`): Address {
  // Take the last 20 bytes (40 hex chars) to form an address
  const addressHex = `0x${didHash.slice(-40)}` as `0x${string}`
  return getAddress(addressHex)
}

/**
 * Convert a DID directly to a DID Address
 * @param did - The DID string
 * @returns Checksummed Ethereum address for use as EAS recipient
 */
export function didToAddress(did: string): Address {
  const didHash = computeDidHash(did)
  return computeDidAddress(didHash)
}

/**
 * Convert a URL directly to a DID Address
 * @param url - The URL to convert
 * @returns Checksummed Ethereum address for use as EAS recipient
 */
export function urlToDidAddress(url: string): Address {
  const did = urlToDid(url)
  return didToAddress(did)
}

/**
 * Validate that a DID Address was computed correctly
 * @param did - The original DID
 * @param address - The address to validate
 * @returns True if the address matches the DID
 */
export function validateDidAddress(did: string, address: string): boolean {
  try {
    const expectedAddress = didToAddress(did)
    return expectedAddress.toLowerCase() === address.toLowerCase()
  } catch {
    return false
  }
}
