// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Sha2Ext} from "./Sha2Ext.sol";
import {Asn1Decode, Asn1Ptr, LibAsn1Ptr} from "./Asn1Decode.sol";
import {ECDSA384} from "../solarity/libs/crypto/ECDSA384.sol";
import {ECDSA384Curve} from "./ECDSA384Curve.sol";
import {LibBytes} from "./LibBytes.sol";
import {ICertManager} from "./ICertManager.sol";

// adapted from https://github.com/marlinprotocol/NitroProver/blob/f1d368d1f172ad3a55cd2aaaa98ad6a6e7dcde9d/src/CertManager.sol

// Manages a mapping of verified certificates and their metadata.
// The root of trust is the AWS Nitro root cert.
// Certificate revocation is not currently supported.
contract CertManager is ICertManager {
    using Asn1Decode for bytes;
    using LibAsn1Ptr for Asn1Ptr;
    using LibBytes for bytes;

    event CertVerified(bytes32 indexed certHash);

    // root CA certificate constants (don't store it to reduce contract size)
    bytes32 public constant ROOT_CA_CERT_HASH = 0x311d96fcd5c5e0ccf72ef548e2ea7d4c0cd53ad7c4cc49e67471aed41d61f185;
    uint64 public constant ROOT_CA_CERT_NOT_AFTER = 2519044085;
    int64 public constant ROOT_CA_CERT_MAX_PATH_LEN = -1;
    bytes32 public constant ROOT_CA_CERT_SUBJECT_HASH =
        0x3c3e2e5f1dd14dee5db88341ba71521e939afdb7881aa24c9f1e1c007a2fa8b6;
    bytes public constant ROOT_CA_CERT_PUB_KEY =
        hex"fc0254eba608c1f36870e29ada90be46383292736e894bfff672d989444b5051e534a4b1f6dbe3c0bc581a32b7b176070ede12d69a3fea211b66e752cf7dd1dd095f6f1370f4170843d9dc100121e4cf63012809664487c9796284304dc53ff4";

    // OID 1.2.840.10045.4.3.3 represents {iso(1) member-body(2) us(840) ansi-x962(10045) signatures(4) ecdsa-with-SHA2(3) ecdsa-with-SHA384(3)}
    // which essentially means the signature algorithm is Elliptic curve Digital Signature Algorithm (DSA) coupled with the Secure Hash Algorithm 384 (SHA384) algorithm
    // @dev Sig algo is hardcoded here because the root certificate's sig algorithm is known beforehand
    // @dev reference article for encoding https://learn.microsoft.com/en-in/windows/win32/seccertenroll/about-object-identifier
    bytes32 public constant CERT_ALGO_OID = 0x53ce037f0dfaa43ef13b095f04e68a6b5e3f1519a01a3203a1e6440ba915b87e; // keccak256(hex"06082a8648ce3d040303")
    // https://oid-rep.orange-labs.fr/get/1.2.840.10045.2.1
    // 1.2.840.10045.2.1 {iso(1) member-body(2) us(840) ansi-x962(10045) keyType(2) ecPublicKey(1)} represents Elliptic curve public key cryptography
    bytes32 public constant EC_PUB_KEY_OID = 0xb60fee1fd85f867dd7c8d16884a49a20287ebe4c0fb49294e9825988aa8e42b4; // keccak256(hex"2a8648ce3d0201")
    // https://oid-rep.orange-labs.fr/get/1.3.132.0.34
    // 1.3.132.0.34 {iso(1) identified-organization(3) certicom(132) curve(0) ansip384r1(34)} represents NIST 384-bit elliptic curve
    bytes32 public constant SECP_384_R1_OID = 0xbd74344bb507daeb9ed315bc535f24a236ccab72c5cd6945fb0efe5c037e2097; // keccak256(hex"2b81040022")

    // extension OID certificate constants
    bytes32 public constant BASIC_CONSTRAINTS_OID = 0x6351d72a43cb42fb9a2531a28608c278c89629f8f025b5f5dc705f3fe45e950a; // keccak256(hex"551d13")
    bytes32 public constant KEY_USAGE_OID = 0x45529d8772b07ebd6d507a1680da791f4a2192882bf89d518801579f7a5167d2; // keccak256(hex"551d0f")

    // certHash -> VerifiedCert
    mapping(bytes32 => bytes) public verified;

    constructor() {
        _saveVerified(
            ROOT_CA_CERT_HASH,
            VerifiedCert({
                ca: true,
                notAfter: ROOT_CA_CERT_NOT_AFTER,
                maxPathLen: ROOT_CA_CERT_MAX_PATH_LEN,
                subjectHash: ROOT_CA_CERT_SUBJECT_HASH,
                pubKey: ROOT_CA_CERT_PUB_KEY
            })
        );
    }

    function verifyCACert(bytes memory cert, bytes32 parentCertHash) external returns (bytes32) {
        bytes32 certHash = keccak256(cert);
        _verifyCert(cert, certHash, true, _loadVerified(parentCertHash));
        return certHash;
    }

    function verifyClientCert(bytes memory cert, bytes32 parentCertHash) external returns (VerifiedCert memory) {
        return _verifyCert(cert, keccak256(cert), false, _loadVerified(parentCertHash));
    }

    function _verifyCert(bytes memory certificate, bytes32 certHash, bool ca, VerifiedCert memory parent)
        internal
        returns (VerifiedCert memory)
    {
        if (certHash != ROOT_CA_CERT_HASH) {
            require(parent.pubKey.length > 0, "parent cert unverified");
            require(parent.notAfter >= block.timestamp, "parent cert expired");
            require(parent.ca, "parent cert is not a CA");
            require(!ca || parent.maxPathLen != 0, "maxPathLen exceeded");
        }

        // skip verification if already verified
        VerifiedCert memory cert = _loadVerified(certHash);
        if (cert.pubKey.length != 0) {
            require(cert.notAfter >= block.timestamp, "cert expired");
            require(cert.ca == ca, "cert is not a CA");
            return cert;
        }

        Asn1Ptr root = certificate.root();
        Asn1Ptr tbsCertPtr = certificate.firstChildOf(root);
        (uint64 notAfter, int64 maxPathLen, bytes32 issuerHash, bytes32 subjectHash, bytes memory pubKey) =
            _parseTbs(certificate, tbsCertPtr, ca);

        require(parent.subjectHash == issuerHash, "issuer / subject mismatch");

        // constrain maxPathLen to parent's maxPathLen-1
        if (parent.maxPathLen > 0 && (maxPathLen < 0 || maxPathLen >= parent.maxPathLen)) {
            maxPathLen = parent.maxPathLen - 1;
        }

        _verifyCertSignature(certificate, tbsCertPtr, parent.pubKey);

        cert = VerifiedCert({
            ca: ca, notAfter: notAfter, maxPathLen: maxPathLen, subjectHash: subjectHash, pubKey: pubKey
        });
        _saveVerified(certHash, cert);

        emit CertVerified(certHash);

        return cert;
    }

    function _parseTbs(bytes memory certificate, Asn1Ptr ptr, bool ca)
        internal
        view
        returns (uint64 notAfter, int64 maxPathLen, bytes32 issuerHash, bytes32 subjectHash, bytes memory pubKey)
    {
        Asn1Ptr versionPtr = certificate.firstChildOf(ptr);
        Asn1Ptr vPtr = certificate.firstChildOf(versionPtr);
        Asn1Ptr serialPtr = certificate.nextSiblingOf(versionPtr);
        Asn1Ptr sigAlgoPtr = certificate.nextSiblingOf(serialPtr);

        require(certificate.keccak(sigAlgoPtr.content(), sigAlgoPtr.length()) == CERT_ALGO_OID, "invalid cert sig algo");
        uint256 version = certificate.uintAt(vPtr);
        // as extensions are used in cert, version should be 3 (value 2) as per https://datatracker.ietf.org/doc/html/rfc5280#section-4.1.2.1
        require(version == 2, "version should be 3");

        (notAfter, maxPathLen, issuerHash, subjectHash, pubKey) = _parseTbsInner(certificate, sigAlgoPtr, ca);
    }

    function _parseTbsInner(bytes memory certificate, Asn1Ptr sigAlgoPtr, bool ca)
        internal
        view
        returns (uint64 notAfter, int64 maxPathLen, bytes32 issuerHash, bytes32 subjectHash, bytes memory pubKey)
    {
        Asn1Ptr issuerPtr = certificate.nextSiblingOf(sigAlgoPtr);
        issuerHash = certificate.keccak(issuerPtr.content(), issuerPtr.length());
        Asn1Ptr validityPtr = certificate.nextSiblingOf(issuerPtr);
        Asn1Ptr subjectPtr = certificate.nextSiblingOf(validityPtr);
        subjectHash = certificate.keccak(subjectPtr.content(), subjectPtr.length());
        Asn1Ptr subjectPublicKeyInfoPtr = certificate.nextSiblingOf(subjectPtr);
        Asn1Ptr extensionsPtr = certificate.nextSiblingOf(subjectPublicKeyInfoPtr);

        if (certificate[extensionsPtr.header()] == 0x81) {
            // skip optional issuerUniqueID
            extensionsPtr = certificate.nextSiblingOf(extensionsPtr);
        }
        if (certificate[extensionsPtr.header()] == 0x82) {
            // skip optional subjectUniqueID
            extensionsPtr = certificate.nextSiblingOf(extensionsPtr);
        }

        notAfter = _verifyValidity(certificate, validityPtr);
        maxPathLen = _verifyExtensions(certificate, extensionsPtr, ca);
        pubKey = _parsePubKey(certificate, subjectPublicKeyInfoPtr);
    }

    function _parsePubKey(bytes memory certificate, Asn1Ptr subjectPublicKeyInfoPtr)
        internal
        pure
        returns (bytes memory subjectPubKey)
    {
        Asn1Ptr pubKeyAlgoPtr = certificate.firstChildOf(subjectPublicKeyInfoPtr);
        Asn1Ptr pubKeyAlgoIdPtr = certificate.firstChildOf(pubKeyAlgoPtr);
        Asn1Ptr algoParamsPtr = certificate.nextSiblingOf(pubKeyAlgoIdPtr);
        Asn1Ptr subjectPublicKeyPtr = certificate.nextSiblingOf(pubKeyAlgoPtr);
        Asn1Ptr subjectPubKeyPtr = certificate.bitstring(subjectPublicKeyPtr);

        require(
            certificate.keccak(pubKeyAlgoIdPtr.content(), pubKeyAlgoIdPtr.length()) == EC_PUB_KEY_OID,
            "invalid cert algo id"
        );
        require(
            certificate.keccak(algoParamsPtr.content(), algoParamsPtr.length()) == SECP_384_R1_OID,
            "invalid cert algo param"
        );

        uint256 end = subjectPubKeyPtr.content() + subjectPubKeyPtr.length();
        subjectPubKey = certificate.slice(end - 96, 96);
    }

    function _verifyValidity(bytes memory certificate, Asn1Ptr validityPtr) internal view returns (uint64 notAfter) {
        Asn1Ptr notBeforePtr = certificate.firstChildOf(validityPtr);
        Asn1Ptr notAfterPtr = certificate.nextSiblingOf(notBeforePtr);

        uint256 notBefore = certificate.timestampAt(notBeforePtr);
        notAfter = uint64(certificate.timestampAt(notAfterPtr));

        require(notBefore <= block.timestamp, "certificate not valid yet");
        require(notAfter >= block.timestamp, "certificate not valid anymore");
    }

    function _verifyExtensions(bytes memory certificate, Asn1Ptr extensionsPtr, bool ca)
        internal
        pure
        returns (int64 maxPathLen)
    {
        require(certificate[extensionsPtr.header()] == 0xa3, "invalid extensions");
        extensionsPtr = certificate.firstChildOf(extensionsPtr);
        Asn1Ptr extensionPtr = certificate.firstChildOf(extensionsPtr);
        uint256 end = extensionsPtr.content() + extensionsPtr.length();
        bool basicConstraintsFound = false;
        bool keyUsageFound = false;
        maxPathLen = -1;

        while (true) {
            Asn1Ptr oidPtr = certificate.firstChildOf(extensionPtr);
            bytes32 oid = certificate.keccak(oidPtr.content(), oidPtr.length());

            if (oid == BASIC_CONSTRAINTS_OID || oid == KEY_USAGE_OID) {
                Asn1Ptr valuePtr = certificate.nextSiblingOf(oidPtr);

                if (certificate[valuePtr.header()] == 0x01) {
                    // skip optional critical bool
                    require(valuePtr.length() == 1, "invalid critical bool value");
                    valuePtr = certificate.nextSiblingOf(valuePtr);
                }

                valuePtr = certificate.octetString(valuePtr);

                if (oid == BASIC_CONSTRAINTS_OID) {
                    basicConstraintsFound = true;
                    maxPathLen = _verifyBasicConstraintsExtension(certificate, valuePtr, ca);
                } else {
                    keyUsageFound = true;
                    _verifyKeyUsageExtension(certificate, valuePtr, ca);
                }
            }

            if (extensionPtr.content() + extensionPtr.length() == end) {
                break;
            }
            extensionPtr = certificate.nextSiblingOf(extensionPtr);
        }

        require(basicConstraintsFound, "basicConstraints not found");
        require(keyUsageFound, "keyUsage not found");
        require(ca || maxPathLen == -1, "maxPathLen must be undefined for client cert");
    }

    function _verifyBasicConstraintsExtension(bytes memory certificate, Asn1Ptr valuePtr, bool ca)
        internal
        pure
        returns (int64 maxPathLen)
    {
        maxPathLen = -1;
        Asn1Ptr basicConstraintsPtr = certificate.firstChildOf(valuePtr);
        bool isCA;
        if (certificate[basicConstraintsPtr.header()] == 0x01) {
            require(basicConstraintsPtr.length() == 1, "invalid isCA bool value");
            isCA = certificate[basicConstraintsPtr.content()] == 0xff;
            basicConstraintsPtr = certificate.nextSiblingOf(basicConstraintsPtr);
        }
        require(ca == isCA, "isCA must be true for CA certs");
        if (certificate[basicConstraintsPtr.header()] == 0x02) {
            maxPathLen = int64(uint64(certificate.uintAt(basicConstraintsPtr)));
        }
    }

    function _verifyKeyUsageExtension(bytes memory certificate, Asn1Ptr valuePtr, bool ca) internal pure {
        uint256 value = certificate.bitstringUintAt(valuePtr);
        // bits are reversed (DigitalSignature 0x01 => 0x80, CertSign 0x32 => 0x04)
        if (ca) {
            require(value & 0x04 == 0x04, "CertSign must be present");
        } else {
            require(value & 0x80 == 0x80, "DigitalSignature must be present");
        }
    }

    function _verifyCertSignature(bytes memory certificate, Asn1Ptr ptr, bytes memory pubKey) internal view {
        Asn1Ptr sigAlgoPtr = certificate.nextSiblingOf(ptr);
        require(certificate.keccak(sigAlgoPtr.content(), sigAlgoPtr.length()) == CERT_ALGO_OID, "invalid cert sig algo");

        bytes memory hash = Sha2Ext.sha384(certificate, ptr.header(), ptr.totalLength());

        Asn1Ptr sigPtr = certificate.nextSiblingOf(sigAlgoPtr);
        Asn1Ptr sigBPtr = certificate.bitstring(sigPtr);
        Asn1Ptr sigRoot = certificate.rootOf(sigBPtr);
        Asn1Ptr sigRPtr = certificate.firstChildOf(sigRoot);
        Asn1Ptr sigSPtr = certificate.nextSiblingOf(sigRPtr);
        (uint128 rhi, uint256 rlo) = certificate.uint384At(sigRPtr);
        (uint128 shi, uint256 slo) = certificate.uint384At(sigSPtr);
        bytes memory sigPacked = abi.encodePacked(rhi, rlo, shi, slo);

        _verifySignature(pubKey, hash, sigPacked);
    }

    function _verifySignature(bytes memory pubKey, bytes memory hash, bytes memory sig) internal view {
        require(ECDSA384.verify(ECDSA384Curve.p384(), hash, sig, pubKey), "invalid sig");
    }

    function _saveVerified(bytes32 certHash, VerifiedCert memory cert) internal {
        verified[certHash] = abi.encodePacked(cert.ca, cert.notAfter, cert.maxPathLen, cert.subjectHash, cert.pubKey);
    }

    function _loadVerified(bytes32 certHash) internal view returns (VerifiedCert memory) {
        bytes memory packed = verified[certHash];
        if (packed.length == 0) {
            return VerifiedCert({ca: false, notAfter: 0, maxPathLen: 0, subjectHash: 0, pubKey: ""});
        }
        uint8 ca;
        uint64 notAfter;
        int64 maxPathLen;
        bytes32 subjectHash;
        assembly {
            ca := mload(add(packed, 0x1))
            notAfter := mload(add(packed, 0x9))
            maxPathLen := mload(add(packed, 0x11))
            subjectHash := mload(add(packed, 0x31))
        }
        bytes memory pubKey = packed.slice(0x31, packed.length - 0x31);
        return VerifiedCert({
            ca: ca != 0, notAfter: notAfter, maxPathLen: maxPathLen, subjectHash: subjectHash, pubKey: pubKey
        });
    }
}
