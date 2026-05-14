// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Mock Sparsity zk verifier for testing the SparsityTEEVerifier adapter.
/// @dev Simulates ISparsityVerifier.verifyProof behavior.
contract MockSparsityVerifier {
    bool public shouldPass;

    constructor(bool _shouldPass) {
        shouldPass = _shouldPass;
    }

    function setShouldPass(bool _shouldPass) external {
        shouldPass = _shouldPass;
    }

    /// @notice Mock verifyProof — always returns shouldPass, ignores inputs.
    function verifyProof(bytes calldata, bytes calldata) external view returns (bool) {
        return shouldPass;
    }
}
