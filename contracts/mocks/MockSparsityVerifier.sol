// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Mock implementing Sparsity's canonical IVerifier interface for testing.
/// @dev Drop-in replacement for DCAPVerifier/NitroVerifier in unit tests.
///      Real verifiers do CBOR/ASN.1 cert chain validation; this just returns
///      whatever fixture values the test sets up.
contract MockSparsityVerifier {
    bytes32 public codeMeasurement;
    bytes public pubKey;
    bytes public userData;
    bool public shouldRevert;

    function setOutput(bytes32 _codeMeasurement, bytes calldata _pubKey, bytes calldata _userData) external {
        codeMeasurement = _codeMeasurement;
        pubKey = _pubKey;
        userData = _userData;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @notice Mock verify — returns fixture values, or reverts to simulate invalid attestation.
    /// @dev Matches canonical sparsity-xyz/8004-tee-registry-ri IVerifier signature.
    function verify(bytes calldata /* attestation */)
        external
        view
        returns (bytes32, bytes memory, bytes memory)
    {
        require(!shouldRevert, "mock: invalid attestation");
        return (codeMeasurement, pubKey, userData);
    }
}
