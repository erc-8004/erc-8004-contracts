// SPDX-License-Identifier: MIT

// Copyright (c) 2019 Jonah Groendal

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity ^0.8.15;

// adapted from https://github.com/JonahGroendal/asn1-decode/tree/master

import {LibBytes} from "./LibBytes.sol";

type Asn1Ptr is uint256;

library LibAsn1Ptr {
    using LibAsn1Ptr for Asn1Ptr;

    // First byte index of the header
    function header(Asn1Ptr self) internal pure returns (uint256) {
        return uint80(Asn1Ptr.unwrap(self));
    }

    // First byte index of the content
    function content(Asn1Ptr self) internal pure returns (uint256) {
        return uint80(Asn1Ptr.unwrap(self) >> 80);
    }

    // Content length
    function length(Asn1Ptr self) internal pure returns (uint256) {
        return uint80(Asn1Ptr.unwrap(self) >> 160);
    }

    // Total length (header length + content length)
    function totalLength(Asn1Ptr self) internal pure returns (uint256) {
        return self.length() + self.content() - self.header();
    }

    // Pack 3 uint80s into a uint256
    function toAsn1Ptr(uint256 _header, uint256 _content, uint256 _length) internal pure returns (Asn1Ptr) {
        return Asn1Ptr.wrap(_header | _content << 80 | _length << 160);
    }
}

library Asn1Decode {
    using LibAsn1Ptr for Asn1Ptr;
    using LibBytes for bytes;

    /*
     * @dev Get the root node. First step in traversing an ASN1 structure
     * @param der The DER-encoded ASN1 structure
     * @return A pointer to the outermost node
     */
    function root(bytes memory der) internal pure returns (Asn1Ptr) {
        return readNodeLength(der, 0);
    }

    /*
     * @dev Get a child root of the current node
     * @param der The DER-encoded ASN1 structure
     * @param ptr Pointer to the current node
     * @return A pointer to the child root node
     */
    function rootOf(bytes memory der, Asn1Ptr ptr) internal pure returns (Asn1Ptr) {
        return readNodeLength(der, ptr.content());
    }

    /*
     * @dev Get the next sibling node
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return A pointer to the next sibling node
     */
    function nextSiblingOf(bytes memory der, Asn1Ptr ptr) internal pure returns (Asn1Ptr) {
        return readNodeLength(der, ptr.content() + ptr.length());
    }

    /*
     * @dev Get the first child node of the current node
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return A pointer to the first child node
     */
    function firstChildOf(bytes memory der, Asn1Ptr ptr) internal pure returns (Asn1Ptr) {
        require(der[ptr.header()] & 0x20 == 0x20, "Not a constructed type");
        return readNodeLength(der, ptr.content());
    }

    /*
     * @dev Extract pointer of bitstring node from DER-encoded structure
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return A pointer to a bitstring
     */
    function bitstring(bytes memory der, Asn1Ptr ptr) internal pure returns (Asn1Ptr) {
        require(der[ptr.header()] == 0x03, "Not type BIT STRING");
        // Only 00 padded bitstr can be converted to bytestr!
        require(der[ptr.content()] == 0x00, "Non-0-padded BIT STRING");
        return LibAsn1Ptr.toAsn1Ptr(ptr.header(), ptr.content() + 1, ptr.length() - 1);
    }

    /*
     * @dev Extract value of bitstring node from DER-encoded structure
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return A bitstring encoded in a uint256
     */
    function bitstringUintAt(bytes memory der, Asn1Ptr ptr) internal pure returns (uint256) {
        require(der[ptr.header()] == 0x03, "Not type BIT STRING");
        uint256 len = ptr.length() - 1;
        return uint256(readBytesN(der, ptr.content() + 1, len) >> ((32 - len) * 8));
    }

    /*
     * @dev Extract value of octet string node from DER-encoded structure
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return A pointer to an octet string
     */
    function octetString(bytes memory der, Asn1Ptr ptr) internal pure returns (Asn1Ptr) {
        require(der[ptr.header()] == 0x04, "Not type OCTET STRING");
        return readNodeLength(der, ptr.content());
    }

    /*
     * @dev Extract value of node from DER-encoded structure
     * @param der The der-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return Uint value of node
     */
    function uintAt(bytes memory der, Asn1Ptr ptr) internal pure returns (uint256) {
        require(der[ptr.header()] == 0x02, "Not type INTEGER");
        require(der[ptr.content()] & 0x80 == 0, "Not positive");
        uint256 len = ptr.length();
        return uint256(readBytesN(der, ptr.content(), len) >> (32 - len) * 8);
    }

    /*
     * @dev Extract value of a positive integer node from DER-encoded structure
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return 384-bit uint encoded in uint128 and uint256
     */
    function uint384At(bytes memory der, Asn1Ptr ptr) internal pure returns (uint128, uint256) {
        require(der[ptr.header()] == 0x02, "Not type INTEGER");
        require(der[ptr.content()] & 0x80 == 0, "Not positive");
        uint256 valueLength = ptr.length();
        uint256 start = ptr.content();
        if (der[start] == 0) {
            start++;
            valueLength--;
        }
        return (
            uint128(uint256(readBytesN(der, start, 16) >> 128)),
            uint256(readBytesN(der, start + 16, valueLength - 16) >> (48 - valueLength) * 8)
        );
    }

    /*
     * @dev Extract value of a timestamp from DER-encoded structure
     * @param der The DER-encoded ASN1 structure
     * @param ptr Points to the indices of the current node
     * @return UNIX timestamp (seconds since 1970/01/01)
     */
    function timestampAt(bytes memory der, Asn1Ptr ptr) internal pure returns (uint256) {
        uint8 _type = uint8(der[ptr.header()]);
        uint256 offset = ptr.content();
        uint256 length = ptr.length();

        // content validation:
        require((_type == 0x17 && length == 13) || (_type == 0x18 && length == 15), "Invalid TIMESTAMP");
        require(der[offset + length - 1] == 0x5A, "TIMESTAMP must be UTC"); // 0x5A == 'Z'
        for (uint256 i = 0; i < length - 1; i++) {
            // all other characters must be digits between 0 and 9
            uint8 v = uint8(der[offset + i]);
            require(48 <= v && v <= 57, "Invalid character in TIMESTAMP");
        }

        uint16 _years;
        if (length == 13) {
            _years = (uint8(der[offset]) - 48 < 5) ? 2000 : 1900;
        } else {
            _years = (uint8(der[offset]) - 48) * 1000 + (uint8(der[offset + 1]) - 48) * 100;
            offset += 2;
        }
        _years += (uint8(der[offset]) - 48) * 10 + uint8(der[offset + 1]) - 48;
        uint8 _months = (uint8(der[offset + 2]) - 48) * 10 + uint8(der[offset + 3]) - 48;
        uint8 _days = (uint8(der[offset + 4]) - 48) * 10 + uint8(der[offset + 5]) - 48;
        uint8 _hours = (uint8(der[offset + 6]) - 48) * 10 + uint8(der[offset + 7]) - 48;
        uint8 _mins = (uint8(der[offset + 8]) - 48) * 10 + uint8(der[offset + 9]) - 48;
        uint8 _secs = (uint8(der[offset + 10]) - 48) * 10 + uint8(der[offset + 11]) - 48;

        return timestampFromDateTime(_years, _months, _days, _hours, _mins, _secs);
    }

    function readNodeLength(bytes memory der, uint256 ix) private pure returns (Asn1Ptr) {
        require(der[ix] & 0x1f != 0x1f, "ASN.1 tags longer than 1-byte are not supported");
        uint256 length;
        uint256 ixFirstContentByte;
        if ((der[ix + 1] & 0x80) == 0) {
            length = uint8(der[ix + 1]);
            ixFirstContentByte = ix + 2;
        } else {
            uint8 lengthbytesLength = uint8(der[ix + 1] & 0x7F);
            if (lengthbytesLength == 1) {
                length = uint8(der[ix + 2]);
            } else if (lengthbytesLength == 2) {
                length = der.readUint16(ix + 2);
            } else {
                length = uint256(readBytesN(der, ix + 2, lengthbytesLength) >> (32 - lengthbytesLength) * 8);
                require(length <= 2 ** 64 - 1); // bound to max uint64 to be safe
            }
            ixFirstContentByte = ix + 2 + lengthbytesLength;
        }
        return LibAsn1Ptr.toAsn1Ptr(ix, ixFirstContentByte, length);
    }

    function readBytesN(bytes memory self, uint256 idx, uint256 len) private pure returns (bytes32 ret) {
        require(len <= 32);
        require(idx + len <= self.length);
        assembly {
            let mask := not(sub(exp(256, sub(32, len)), 1))
            ret := and(mload(add(add(self, 32), idx)), mask)
        }
    }

    // Calculate the number of seconds from 1970/01/01 to
    // year/month/day/hour/minute/second using the date conversion
    // algorithm from https://aa.usno.navy.mil/faq/JD_formula.html
    // and subtracting the offset 2440588 so that 1970/01/01 is day 0
    function timestampFromDateTime(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 second
    ) private pure returns (uint256) {
        require(year >= 1970);
        require(1 <= month && month <= 12);
        require(1 <= day && day <= 31);
        require(hour <= 23);
        require(minute <= 59);
        require(second <= 59);

        unchecked {
            int256 _year = int256(year);
            int256 _month = int256(month);
            int256 _day = int256(day);

            int256 _days = _day - 32075 + 1461 * (_year + 4800 + (_month - 14) / 12) / 4 + 367
                * (_month - 2 - (_month - 14) / 12 * 12) / 12 - 3 * ((_year + 4900 + (_month - 14) / 12) / 100) / 4
                - 2440588;

            return ((uint256(_days) * 24 + hour) * 60 + minute) * 60 + second;
        }
    }
}
