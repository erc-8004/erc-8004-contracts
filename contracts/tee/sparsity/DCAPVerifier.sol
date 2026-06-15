// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "./TEERegistry.sol";
import {IAttestation} from "../automata/IAttestation.sol";

/// @title DCAPVerifier — Intel TDX/SGX attestation via Automata DCAP
/// @notice Wraps Automata's on-chain DCAP verifier. Expects a raw DCAP quote as input.
/// @dev Gas cost: ~4-5M per verification (real on-chain DCAP parsing + cert chain validation).
///
/// Automata output layout (from AutomataDcapV3Attestation._verify):
///   byte  0       : uint8  tcbStatus
///   bytes 1–32    : bytes32 mrEnclave
///   bytes 33–64   : bytes32 mrSigner
///   bytes 65–128  : bytes64 reportData
contract DCAPVerifier is IVerifier {
    IAttestation public immutable automata;

    constructor(address _automata) {
        automata = IAttestation(_automata);
    }

    function verify(bytes calldata attestation)
        external
        override
        returns (bytes32 codeMeasurement, bytes memory pubKey, bytes memory userData)
    {
        bytes memory output = automata.verifyAndAttestOnChain(attestation);

        bytes32 mrEnclave;
        bytes32 mrSigner;
        assembly {
            mrEnclave := mload(add(output, 33))
            mrSigner := mload(add(output, 65))
        }

        codeMeasurement = keccak256(abi.encodePacked(mrEnclave, mrSigner));

        // reportData occupies bytes 65–128 (64 bytes) of the Automata output
        userData = new bytes(64);
        assembly {
            // output + 32 (length prefix) + 65 (offset) = output + 97
            let src := add(output, 97)
            let dst := add(userData, 32)
            mstore(dst, mload(src))
            mstore(add(dst, 32), mload(add(src, 32)))
        }

        // DCAP does not expose a separate public key
        pubKey = "";
    }
}
