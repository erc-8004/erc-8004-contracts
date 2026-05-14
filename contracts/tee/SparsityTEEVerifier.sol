// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TEERegistryUpgradeable.sol";

/// @notice Interface for Sparsity's zk co-processor verifier.
/// @dev Sparsity TEEAgentRegistry exposes verifyProof for attestation verification.
interface ISparsityVerifier {
    function verifyProof(bytes calldata publicValues, bytes calldata proofBytes) external view returns (bool);
}

/// @notice Adapter that bridges ERC-8004 TEERegistry to Sparsity's zk verifier.
/// @dev Proof format: abi.encode(publicValues, proofBytes)
///      publicValues contains: teeArch (uint256), codeMeasurement (bytes32),
///      teePubkey (address), agentWalletAddress (address)
///      This matches Sparsity's 8004-ri-tutorial registration flow.
contract SparsityTEEVerifier is ITEEVerifier {
    ISparsityVerifier public immutable sparsityVerifier;

    /// @param _sparsityVerifier Address of Sparsity's deployed verifier contract
    ///        (e.g. TEEAgentRegistry on Base Sepolia: 0xe718ae...)
    constructor(address _sparsityVerifier) {
        require(_sparsityVerifier != address(0), "zero verifier");
        sparsityVerifier = ISparsityVerifier(_sparsityVerifier);
    }

    /// @notice Verify a Sparsity-format TEE attestation proof.
    /// @param proof abi.encode(publicValues, proofBytes) — Sparsity's proof bundle.
    /// @param pubKey The EVM address claimed as the TEE public key.
    /// @return success Whether the zk proof verified successfully.
    /// @return identifiers [codeMeasurement, teeArch] as bytes32 array.
    function verify(bytes calldata proof, address pubKey)
        external
        view
        returns (bool success, bytes32[] memory identifiers)
    {
        // Decode Sparsity proof bundle
        (bytes memory publicValues, bytes memory proofBytes) =
            abi.decode(proof, (bytes, bytes));

        // Run zk verification via Sparsity's verifier
        success = sparsityVerifier.verifyProof(publicValues, proofBytes);
        if (!success) {
            return (false, new bytes32[](0));
        }

        // Decode publicValues to extract identifiers and verify pubkey
        // Layout: (uint256 teeArch, bytes32 codeMeasurement, address teePubkey, address agentWalletAddress)
        (uint256 teeArch, bytes32 codeMeasurement, address teePubkey, ) =
            abi.decode(publicValues, (uint256, bytes32, address, address));

        // Verify the claimed pubKey matches the attested teePubkey
        if (teePubkey != pubKey) {
            return (false, new bytes32[](0));
        }

        // Return identifiers for reverse lookup
        identifiers = new bytes32[](2);
        identifiers[0] = codeMeasurement;
        identifiers[1] = bytes32(teeArch);

        return (true, identifiers);
    }
}
