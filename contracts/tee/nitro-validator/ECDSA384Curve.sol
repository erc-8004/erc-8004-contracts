// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ECDSA384} from "../solarity/libs/crypto/ECDSA384.sol";

library ECDSA384Curve {
    // ECDSA384 curve parameters (NIST P-384)
    bytes public constant CURVE_A =
        hex"fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000fffffffc";
    bytes public constant CURVE_B =
        hex"b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef";
    bytes public constant CURVE_GX =
        hex"aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7";
    bytes public constant CURVE_GY =
        hex"3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f";
    bytes public constant CURVE_P =
        hex"fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff";
    bytes public constant CURVE_N =
        hex"ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973";
    // use n-1 for lowSmax, which allows s-values above n/2
    bytes public constant CURVE_LOW_S_MAX =
        hex"ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52972";

    function p384() internal pure returns (ECDSA384.Parameters memory) {
        return ECDSA384.Parameters({
            a: CURVE_A, b: CURVE_B, gx: CURVE_GX, gy: CURVE_GY, p: CURVE_P, n: CURVE_N, lowSmax: CURVE_LOW_S_MAX
        });
    }
}
