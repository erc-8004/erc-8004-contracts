// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

library LibBytes {
    function keccak(bytes memory data, uint256 offset, uint256 length) internal pure returns (bytes32 result) {
        require(offset + length <= data.length, "index out of bounds");
        assembly {
            result := keccak256(add(data, add(32, offset)), length)
        }
    }

    function slice(bytes memory b, uint256 offset, uint256 length) internal pure returns (bytes memory result) {
        require(offset + length <= b.length, "index out of bounds");

        // Create a new bytes structure and copy contents
        result = new bytes(length);
        uint256 dest;
        uint256 src;
        assembly {
            dest := add(result, 32)
            src := add(b, add(32, offset))
        }
        memcpy(dest, src, length);
        return result;
    }

    function readUint16(bytes memory b, uint256 index) internal pure returns (uint16) {
        require(b.length >= index + 2, "index out of bounds");
        bytes2 result;
        assembly {
            result := mload(add(b, add(index, 32)))
        }
        return uint16(result);
    }

    function readUint32(bytes memory b, uint256 index) internal pure returns (uint32) {
        require(b.length >= index + 4, "index out of bounds");
        bytes4 result;
        assembly {
            result := mload(add(b, add(index, 32)))
        }
        return uint32(result);
    }

    function readUint64(bytes memory b, uint256 index) internal pure returns (uint64) {
        require(b.length >= index + 8, "index out of bounds");
        bytes8 result;
        assembly {
            result := mload(add(b, add(index, 32)))
        }
        return uint64(result);
    }

    function memcpy(uint256 dest, uint256 src, uint256 len) internal pure {
        // Copy word-length chunks while possible
        for (; len >= 32; len -= 32) {
            assembly {
                mstore(dest, mload(src))
            }
            dest += 32;
            src += 32;
        }

        if (len > 0) {
            // Copy remaining bytes
            uint256 mask = 256 ** (32 - len) - 1;
            assembly {
                let srcpart := and(mload(src), not(mask))
                let destpart := and(mload(dest), mask)
                mstore(dest, or(destpart, srcpart))
            }
        }
    }
}
