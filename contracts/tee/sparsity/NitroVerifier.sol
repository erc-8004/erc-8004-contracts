// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVerifier} from "./TEERegistry.sol";
import {NitroValidator} from "../nitro-validator/NitroValidator.sol";
import {CborDecode, CborElement, LibCborElement} from "../nitro-validator/CborDecode.sol";

/// @title NitroVerifier — AWS Nitro Enclaves attestation via on-chain COSE/X.509 validation
/// @notice Wraps base/nitro-validator behind IVerifier. Accepts raw COSE_Sign1 attestation bytes.
/// @dev Gas cost: ~63M per verification (CBOR parsing, ASN.1 cert chain, ECDSA-384 sig check).
///      Fits within Base L2 block gas limit (150M).
///
/// Code measurement = keccak256(PCR0 || PCR1 || PCR2):
///   PCR0 = enclave image hash
///   PCR1 = kernel/boot hash
///   PCR2 = application hash
contract NitroVerifier is IVerifier {
    using CborDecode for bytes;
    using LibCborElement for CborElement;

    NitroValidator public immutable validator;

    constructor(NitroValidator _validator) {
        validator = _validator;
    }

    function verify(bytes calldata attestation)
        external
        override
        returns (bytes32 codeMeasurement, bytes memory pubKey, bytes memory userData)
    {
        (bytes memory attestationTbs, bytes memory signature) = validator.decodeAttestationTbs(attestation);
        NitroValidator.Ptrs memory ptrs = validator.validateAttestation(attestationTbs, signature);

        bytes memory pcr0 = attestationTbs.slice(ptrs.pcrs[0]);
        bytes memory pcr1 = attestationTbs.slice(ptrs.pcrs[1]);
        bytes memory pcr2 = attestationTbs.slice(ptrs.pcrs[2]);

        codeMeasurement = keccak256(abi.encodePacked(pcr0, pcr1, pcr2));

        pubKey = ptrs.publicKey.isNull() ? bytes("") : attestationTbs.slice(ptrs.publicKey);
        userData = ptrs.userData.isNull() ? bytes("") : attestationTbs.slice(ptrs.userData);
    }
}
