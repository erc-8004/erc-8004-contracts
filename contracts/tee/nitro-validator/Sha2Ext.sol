// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// adapted from https://github.com/yangfh2004/SolSha2Ext/blob/main/contracts/lib/Sha2Ext.sol

import {LibBytes} from "./LibBytes.sol";

library Sha2Ext {
    using LibBytes for bytes;

    function sha2(bytes memory message, uint256 offset, uint256 length, uint64[8] memory h) internal pure {
        uint64[80] memory k = [
            0x428a2f98d728ae22,
            0x7137449123ef65cd,
            0xb5c0fbcfec4d3b2f,
            0xe9b5dba58189dbbc,
            0x3956c25bf348b538,
            0x59f111f1b605d019,
            0x923f82a4af194f9b,
            0xab1c5ed5da6d8118,
            0xd807aa98a3030242,
            0x12835b0145706fbe,
            0x243185be4ee4b28c,
            0x550c7dc3d5ffb4e2,
            0x72be5d74f27b896f,
            0x80deb1fe3b1696b1,
            0x9bdc06a725c71235,
            0xc19bf174cf692694,
            0xe49b69c19ef14ad2,
            0xefbe4786384f25e3,
            0x0fc19dc68b8cd5b5,
            0x240ca1cc77ac9c65,
            0x2de92c6f592b0275,
            0x4a7484aa6ea6e483,
            0x5cb0a9dcbd41fbd4,
            0x76f988da831153b5,
            0x983e5152ee66dfab,
            0xa831c66d2db43210,
            0xb00327c898fb213f,
            0xbf597fc7beef0ee4,
            0xc6e00bf33da88fc2,
            0xd5a79147930aa725,
            0x06ca6351e003826f,
            0x142929670a0e6e70,
            0x27b70a8546d22ffc,
            0x2e1b21385c26c926,
            0x4d2c6dfc5ac42aed,
            0x53380d139d95b3df,
            0x650a73548baf63de,
            0x766a0abb3c77b2a8,
            0x81c2c92e47edaee6,
            0x92722c851482353b,
            0xa2bfe8a14cf10364,
            0xa81a664bbc423001,
            0xc24b8b70d0f89791,
            0xc76c51a30654be30,
            0xd192e819d6ef5218,
            0xd69906245565a910,
            0xf40e35855771202a,
            0x106aa07032bbd1b8,
            0x19a4c116b8d2d0c8,
            0x1e376c085141ab53,
            0x2748774cdf8eeb99,
            0x34b0bcb5e19b48a8,
            0x391c0cb3c5c95a63,
            0x4ed8aa4ae3418acb,
            0x5b9cca4f7763e373,
            0x682e6ff3d6b2b8a3,
            0x748f82ee5defb2fc,
            0x78a5636f43172f60,
            0x84c87814a1f0ab72,
            0x8cc702081a6439ec,
            0x90befffa23631e28,
            0xa4506cebde82bde9,
            0xbef9a3f7b2c67915,
            0xc67178f2e372532b,
            0xca273eceea26619c,
            0xd186b8c721c0c207,
            0xeada7dd6cde0eb1e,
            0xf57d4f7fee6ed178,
            0x06f067aa72176fba,
            0x0a637dc5a2c898a6,
            0x113f9804bef90dae,
            0x1b710b35131c471b,
            0x28db77f523047d84,
            0x32caab7b40c72493,
            0x3c9ebe0a15c9bebc,
            0x431d67c49c100d4c,
            0x4cc5d4becb3e42b6,
            0x597f299cfc657e2a,
            0x5fcb6fab3ad6faec,
            0x6c44198c4a475817
        ];

        require(offset + length <= message.length, "OUT_OF_BOUNDS");
        bytes memory padding = padMessage(message, offset, length);
        require(padding.length % 128 == 0, "PADDING_ERROR");
        uint64[80] memory w;
        uint64[8] memory temp;
        uint64[16] memory blocks;
        uint256 messageLength = (length / 128) * 128;
        unchecked {
            for (uint256 i = 0; i < (messageLength + padding.length); i += 128) {
                if (i < messageLength) {
                    getBlock(message, blocks, offset + i);
                } else {
                    getBlock(padding, blocks, i - messageLength);
                }
                for (uint256 j = 0; j < 16; ++j) {
                    w[j] = blocks[j];
                }
                for (uint256 j = 16; j < 80; ++j) {
                    w[j] = gamma1(w[j - 2]) + w[j - 7] + gamma0(w[j - 15]) + w[j - 16];
                }
                for (uint256 j = 0; j < 8; ++j) {
                    temp[j] = h[j];
                }
                for (uint256 j = 0; j < 80; ++j) {
                    uint64 t1 = temp[7] + sigma1(temp[4]) + ch(temp[4], temp[5], temp[6]) + k[j] + w[j];
                    uint64 t2 = sigma0(temp[0]) + maj(temp[0], temp[1], temp[2]);
                    temp[7] = temp[6];
                    temp[6] = temp[5];
                    temp[5] = temp[4];
                    temp[4] = temp[3] + t1;
                    temp[3] = temp[2];
                    temp[2] = temp[1];
                    temp[1] = temp[0];
                    temp[0] = t1 + t2;
                }
                for (uint256 j = 0; j < 8; ++j) {
                    h[j] += temp[j];
                }
            }
        }
    }

    function sha384(bytes memory message, uint256 offset, uint256 length) internal pure returns (bytes memory) {
        uint64[8] memory h = [
            0xcbbb9d5dc1059ed8,
            0x629a292a367cd507,
            0x9159015a3070dd17,
            0x152fecd8f70e5939,
            0x67332667ffc00b31,
            0x8eb44a8768581511,
            0xdb0c2e0d64f98fa7,
            0x47b5481dbefa4fa4
        ];
        sha2(message, offset, length, h);
        return abi.encodePacked(bytes8(h[0]), bytes8(h[1]), bytes8(h[2]), bytes8(h[3]), bytes8(h[4]), bytes8(h[5]));
    }

    function sha512(bytes memory message, uint256 offset, uint256 length) internal pure returns (bytes memory) {
        uint64[8] memory h = [
            0x6a09e667f3bcc908,
            0xbb67ae8584caa73b,
            0x3c6ef372fe94f82b,
            0xa54ff53a5f1d36f1,
            0x510e527fade682d1,
            0x9b05688c2b3e6c1f,
            0x1f83d9abfb41bd6b,
            0x5be0cd19137e2179
        ];
        sha2(message, offset, length, h);
        return abi.encodePacked(
            bytes8(h[0]),
            bytes8(h[1]),
            bytes8(h[2]),
            bytes8(h[3]),
            bytes8(h[4]),
            bytes8(h[5]),
            bytes8(h[6]),
            bytes8(h[7])
        );
    }

    function padMessage(bytes memory message, uint256 offset, uint256 length) internal pure returns (bytes memory) {
        bytes8 bitLength = bytes8(uint64(length * 8));
        uint256 mdi = length % 128;
        uint256 paddingLength;
        if (mdi < 112) {
            paddingLength = 119 - mdi;
        } else {
            paddingLength = 247 - mdi;
        }
        bytes memory padding = new bytes(paddingLength);
        bytes memory tail = message.slice(offset + length - mdi, mdi);
        return abi.encodePacked(tail, bytes1(0x80), padding, bitLength);
    }

    function getBlock(bytes memory message, uint64[16] memory blocks, uint256 index) internal pure {
        for (uint256 i = 0; i < 16; ++i) {
            blocks[i] = message.readUint64(index + i * 8);
        }
    }

    function ch(uint64 x, uint64 y, uint64 z) internal pure returns (uint64) {
        return (x & y) ^ (~x & z);
    }

    function maj(uint64 x, uint64 y, uint64 z) internal pure returns (uint64) {
        return (x & y) ^ (x & z) ^ (y & z);
    }

    function sigma0(uint64 x) internal pure returns (uint64) {
        return (rotateRight(x, 28) ^ rotateRight(x, 34) ^ rotateRight(x, 39));
    }

    function sigma1(uint64 x) internal pure returns (uint64) {
        return (rotateRight(x, 14) ^ rotateRight(x, 18) ^ rotateRight(x, 41));
    }

    function gamma0(uint64 x) internal pure returns (uint64) {
        return (rotateRight(x, 1) ^ rotateRight(x, 8) ^ (x >> 7));
    }

    function gamma1(uint64 x) internal pure returns (uint64) {
        return (rotateRight(x, 19) ^ rotateRight(x, 61) ^ (x >> 6));
    }

    function rotateRight(uint64 x, uint64 n) internal pure returns (uint64) {
        return (x << (64 - n)) | (x >> n);
    }
}
