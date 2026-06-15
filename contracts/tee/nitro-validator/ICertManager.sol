// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ICertManager {
    struct VerifiedCert {
        bool ca;
        uint64 notAfter;
        int64 maxPathLen;
        bytes32 subjectHash;
        bytes pubKey;
    }

    function verifyCACert(bytes memory cert, bytes32 parentCertHash) external returns (bytes32);

    function verifyClientCert(bytes memory cert, bytes32 parentCertHash) external returns (VerifiedCert memory);
}
