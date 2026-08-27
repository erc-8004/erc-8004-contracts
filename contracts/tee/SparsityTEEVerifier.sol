// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TEERegistryUpgradeable.sol";

/// @notice Canonical Sparsity RI verifier interface (from sparsity-xyz/8004-tee-registry-ri).
/// @dev Each TEE platform (TDX via DCAPVerifier, Nitro via NitroVerifier) implements this.
///      Non-view: DCAP and Nitro cert-chain validation mutate verifier state for caching.
interface ISparsityIVerifier {
    function verify(bytes calldata attestation)
        external
        returns (bytes32 codeMeasurement, bytes memory pubKey, bytes memory userData);
}

/// @notice Tag identifying which Sparsity TEE platform this adapter is wired to.
/// @dev Stored as identifiers[1] for reverse lookup by platform.
enum SparsityTEEArch {
    TDX,    // matches Sparsity TEEType.TDX (DCAPVerifier — Intel TDX/SGX via Automata DCAP)
    NITRO   // matches Sparsity TEEType.NITRO (NitroVerifier — AWS Nitro Enclaves)
}

/// @title SparsityTEEVerifier
/// @notice Adapter bridging ERC-8004 ITEEVerifier to Sparsity's canonical IVerifier.
/// @dev Wraps a Sparsity per-platform verifier (DCAPVerifier or NitroVerifier).
///      The agent's EVM address must be embedded in the attestation's userData
///      (first 20 bytes), bound to the enclave measurement via TEE-signed attestation.
contract SparsityTEEVerifier is ITEEVerifier {
    /// @notice The underlying Sparsity verifier (DCAPVerifier or NitroVerifier instance).
    ISparsityIVerifier public immutable sparsityVerifier;

    /// @notice Which TEE platform this adapter is wired to (for identifiers[1] tag).
    SparsityTEEArch public immutable teeArch;

    constructor(address _sparsityVerifier, SparsityTEEArch _teeArch) {
        require(_sparsityVerifier != address(0), "zero verifier");
        sparsityVerifier = ISparsityIVerifier(_sparsityVerifier);
        teeArch = _teeArch;
    }

    /// @notice Verify a Sparsity-format TEE attestation.
    /// @param proof Raw attestation bytes (DCAP quote for TDX, COSE_Sign1 for Nitro).
    /// @param pubKey The EVM address claimed as the TEE-controlled agent wallet.
    /// @return success Whether the attestation verified AND userData[0:20] == pubKey.
    /// @return identifiers [codeMeasurement, bytes32(uint256(teeArch))].
    function verify(bytes calldata proof, address pubKey)
        external
        override
        returns (bool success, bytes32[] memory identifiers)
    {
        // Call Sparsity's verifier. Reverts on invalid attestation per IVerifier contract,
        // so wrap in a try/catch and surface as (false, empty) to match ITEEVerifier semantics.
        try sparsityVerifier.verify(proof) returns (
            bytes32 codeMeasurement,
            bytes memory /* attestedPubKey */,
            bytes memory userData
        ) {
            // userData must contain at least the 20-byte EVM address the TEE controls.
            if (userData.length < 20) {
                return (false, new bytes32[](0));
            }

            address attestedAddr;
            assembly {
                // userData is a bytes memory: 32-byte length prefix, then payload.
                // Load first 32 bytes of payload, shift right 96 bits to get top 20 bytes as address.
                attestedAddr := shr(96, mload(add(userData, 32)))
            }

            if (attestedAddr != pubKey) {
                return (false, new bytes32[](0));
            }

            identifiers = new bytes32[](2);
            identifiers[0] = codeMeasurement;
            identifiers[1] = bytes32(uint256(teeArch));
            return (true, identifiers);
        } catch {
            return (false, new bytes32[](0));
        }
    }
}
