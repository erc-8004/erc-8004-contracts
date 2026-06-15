// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ICertManager} from "./ICertManager.sol";
import {Sha2Ext} from "./Sha2Ext.sol";
import {CborDecode, CborElement, LibCborElement} from "./CborDecode.sol";
import {ECDSA384} from "../solarity/libs/crypto/ECDSA384.sol";
import {ECDSA384Curve} from "./ECDSA384Curve.sol";
import {LibBytes} from "./LibBytes.sol";

// adapted from https://github.com/marlinprotocol/NitroProver/blob/f1d368d1f172ad3a55cd2aaaa98ad6a6e7dcde9d/src/NitroProver.sol

contract NitroValidator {
    using LibBytes for bytes;
    using CborDecode for bytes;
    using LibCborElement for CborElement;

    bytes32 public constant ATTESTATION_TBS_PREFIX = 0x63ce814bd924c1ef12c43686e4cbf48ed1639a78387b0570c23ca921e8ce071c; // keccak256(hex"846a5369676e61747572653144a101382240")
    bytes32 public constant ATTESTATION_DIGEST = 0x501a3a7a4e0cf54b03f2488098bdd59bc1c2e8d741a300d6b25926d531733fef; // keccak256("SHA384")

    bytes32 public constant CERTIFICATE_KEY = 0x925cec779426f44d8d555e01d2683a3a765ce2fa7562ca7352aeb09dfc57ea6a; // keccak256(bytes("certificate"))
    bytes32 public constant PUBLIC_KEY_KEY = 0xc7b28019ccfdbd30ffc65951d94bb85c9e2b8434111a000b5afd533ce65f57a4; // keccak256(bytes("public_key"))
    bytes32 public constant MODULE_ID_KEY = 0x8ce577cf664c36ba5130242bf5790c2675e9f4e6986a842b607821bee25372ee; // keccak256(bytes("module_id"))
    bytes32 public constant TIMESTAMP_KEY = 0x4ebf727c48eac2c66272456b06a885c5cc03e54d140f63b63b6fd10c1227958e; // keccak256(bytes("timestamp"))
    bytes32 public constant USER_DATA_KEY = 0x5e4ea5393e4327b3014bc32f2264336b0d1ee84a4cfd197c8ad7e1e16829a16a; // keccak256(bytes("user_data"))
    bytes32 public constant CABUNDLE_KEY = 0x8a8cb7aa1da17ada103546ae6b4e13ccc2fafa17adf5f93925e0a0a4e5681a6a; // keccak256(bytes("cabundle"))
    bytes32 public constant DIGEST_KEY = 0x682a7e258d80bd2421d3103cbe71e3e3b82138116756b97b8256f061dc2f11fb; // keccak256(bytes("digest"))
    bytes32 public constant NONCE_KEY = 0x7ab1577440dd7bedf920cb6de2f9fc6bf7ba98c78c85a3fa1f8311aac95e1759; // keccak256(bytes("nonce"))
    bytes32 public constant PCRS_KEY = 0x61585f8bc67a4b6d5891a4639a074964ac66fc2241dc0b36c157dc101325367a; // keccak256(bytes("pcrs"))

    struct Ptrs {
        CborElement moduleID;
        uint64 timestamp;
        CborElement digest;
        CborElement[] pcrs;
        CborElement cert;
        CborElement[] cabundle;
        CborElement publicKey;
        CborElement userData;
        CborElement nonce;
    }

    ICertManager public immutable certManager;

    constructor(ICertManager _certManager) {
        certManager = _certManager;
    }

    function decodeAttestationTbs(bytes memory attestation)
        external
        pure
        returns (bytes memory attestationTbs, bytes memory signature)
    {
        uint256 offset = 1;
        if (attestation[0] == 0xD2) {
            offset = 2;
        }

        CborElement protectedPtr = attestation.byteStringAt(offset);
        CborElement unprotectedPtr = attestation.nextMap(protectedPtr);
        CborElement payloadPtr = attestation.nextByteString(unprotectedPtr);
        CborElement signaturePtr = attestation.nextByteString(payloadPtr);

        uint256 rawProtectedLength = protectedPtr.end() - offset;
        uint256 rawPayloadLength = payloadPtr.end() - unprotectedPtr.end();
        bytes memory rawProtectedBytes = attestation.slice(offset, rawProtectedLength);
        bytes memory rawPayloadBytes = attestation.slice(unprotectedPtr.end(), rawPayloadLength);
        attestationTbs =
            _constructAttestationTbs(rawProtectedBytes, rawProtectedLength, rawPayloadBytes, rawPayloadLength);
        signature = attestation.slice(signaturePtr.start(), signaturePtr.length());
    }

    function validateAttestation(bytes memory attestationTbs, bytes memory signature) public returns (Ptrs memory) {
        Ptrs memory ptrs = _parseAttestation(attestationTbs);

        require(ptrs.moduleID.length() > 0, "no module id");
        require(ptrs.timestamp > 0, "no timestamp");
        require(ptrs.cabundle.length > 0, "no cabundle");
        require(attestationTbs.keccak(ptrs.digest) == ATTESTATION_DIGEST, "invalid digest");
        require(1 <= ptrs.pcrs.length && ptrs.pcrs.length <= 32, "invalid pcrs");
        require(
            ptrs.publicKey.isNull() || (1 <= ptrs.publicKey.length() && ptrs.publicKey.length() <= 1024),
            "invalid pub key"
        );
        require(ptrs.userData.isNull() || (ptrs.userData.length() <= 512), "invalid user data");
        require(ptrs.nonce.isNull() || (ptrs.nonce.length() <= 512), "invalid nonce");

        for (uint256 i = 0; i < ptrs.pcrs.length; i++) {
            require(
                ptrs.pcrs[i].length() == 32 || ptrs.pcrs[i].length() == 48 || ptrs.pcrs[i].length() == 64, "invalid pcr"
            );
        }

        bytes memory cert = attestationTbs.slice(ptrs.cert);
        bytes[] memory cabundle = new bytes[](ptrs.cabundle.length);
        for (uint256 i = 0; i < ptrs.cabundle.length; i++) {
            require(1 <= ptrs.cabundle[i].length() && ptrs.cabundle[i].length() <= 1024, "invalid cabundle cert");
            cabundle[i] = attestationTbs.slice(ptrs.cabundle[i]);
        }

        ICertManager.VerifiedCert memory parent = verifyCertBundle(cert, cabundle);
        bytes memory hash = Sha2Ext.sha384(attestationTbs, 0, attestationTbs.length);
        _verifySignature(parent.pubKey, hash, signature);

        return ptrs;
    }

    function verifyCertBundle(bytes memory certificate, bytes[] memory cabundle)
        internal
        returns (ICertManager.VerifiedCert memory)
    {
        bytes32 parentHash;
        for (uint256 i = 0; i < cabundle.length; i++) {
            parentHash = certManager.verifyCACert(cabundle[i], parentHash);
        }
        return certManager.verifyClientCert(certificate, parentHash);
    }

    function _constructAttestationTbs(
        bytes memory rawProtectedBytes,
        uint256 rawProtectedLength,
        bytes memory rawPayloadBytes,
        uint256 rawPayloadLength
    ) internal pure returns (bytes memory attestationTbs) {
        attestationTbs = new bytes(13 + rawProtectedLength + rawPayloadLength);
        attestationTbs[0] = bytes1(uint8(4 << 5 | 4)); // Outer: 4-length array
        attestationTbs[1] = bytes1(uint8(3 << 5 | 10)); // Context: 10-length string
        attestationTbs[12 + rawProtectedLength] = bytes1(uint8(2 << 5)); // ExternalAAD: 0-length bytes

        string memory sig = "Signature1";
        uint256 dest;
        uint256 sigSrc;
        uint256 protectedSrc;
        uint256 payloadSrc;
        assembly {
            dest := add(attestationTbs, 32)
            sigSrc := add(sig, 32)
            protectedSrc := add(rawProtectedBytes, 32)
            payloadSrc := add(rawPayloadBytes, 32)
        }

        LibBytes.memcpy(dest + 2, sigSrc, 10);
        LibBytes.memcpy(dest + 12, protectedSrc, rawProtectedLength);
        LibBytes.memcpy(dest + 13 + rawProtectedLength, payloadSrc, rawPayloadLength);
    }

    function _parseAttestation(bytes memory attestationTbs) internal pure returns (Ptrs memory) {
        require(attestationTbs.keccak(0, 18) == ATTESTATION_TBS_PREFIX, "invalid attestation prefix");

        CborElement payload = attestationTbs.byteStringAt(18);
        CborElement current = attestationTbs.mapAt(payload.start());

        Ptrs memory ptrs;
        uint256 end = payload.end();
        while (current.end() < end) {
            current = attestationTbs.nextTextString(current);
            bytes32 keyHash = attestationTbs.keccak(current);
            if (keyHash == MODULE_ID_KEY) {
                current = attestationTbs.nextTextString(current);
                ptrs.moduleID = current;
            } else if (keyHash == DIGEST_KEY) {
                current = attestationTbs.nextTextString(current);
                ptrs.digest = current;
            } else if (keyHash == CERTIFICATE_KEY) {
                current = attestationTbs.nextByteString(current);
                ptrs.cert = current;
            } else if (keyHash == PUBLIC_KEY_KEY) {
                current = attestationTbs.nextByteStringOrNull(current);
                ptrs.publicKey = current;
            } else if (keyHash == USER_DATA_KEY) {
                current = attestationTbs.nextByteStringOrNull(current);
                ptrs.userData = current;
            } else if (keyHash == NONCE_KEY) {
                current = attestationTbs.nextByteStringOrNull(current);
                ptrs.nonce = current;
            } else if (keyHash == TIMESTAMP_KEY) {
                current = attestationTbs.nextPositiveInt(current);
                ptrs.timestamp = uint64(current.value());
            } else if (keyHash == CABUNDLE_KEY) {
                current = attestationTbs.nextArray(current);
                ptrs.cabundle = new CborElement[](current.value());
                for (uint256 i = 0; i < ptrs.cabundle.length; i++) {
                    current = attestationTbs.nextByteString(current);
                    ptrs.cabundle[i] = current;
                }
            } else if (keyHash == PCRS_KEY) {
                current = attestationTbs.nextMap(current);
                ptrs.pcrs = new CborElement[](current.value());
                for (uint256 i = 0; i < ptrs.pcrs.length; i++) {
                    current = attestationTbs.nextPositiveInt(current);
                    uint256 key = current.value();
                    require(key < ptrs.pcrs.length, "invalid pcr key value");
                    require(CborElement.unwrap(ptrs.pcrs[key]) == 0, "duplicate pcr key");
                    current = attestationTbs.nextByteString(current);
                    ptrs.pcrs[key] = current;
                }
            } else {
                revert("invalid attestation key");
            }
        }

        return ptrs;
    }

    function _verifySignature(bytes memory pubKey, bytes memory hash, bytes memory sig) internal view {
        require(ECDSA384.verify(ECDSA384Curve.p384(), hash, sig, pubKey), "invalid sig");
    }
}
