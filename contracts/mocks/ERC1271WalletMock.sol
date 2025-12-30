// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Minimal ERC-1271 wallet mock.
/// It considers a signature valid if it is an ECDSA signature by `signer` over the provided hash.
contract ERC1271WalletMock is IERC1271 {
    using ECDSA for bytes32;

    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes4 private constant ERC1271_FAILVALUE = 0xffffffff;

    address public immutable signer;

    constructor(address _signer) {
        signer = _signer;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address recovered = ECDSA.recover(hash, signature);
        if (recovered == signer) return ERC1271_MAGICVALUE;
        return ERC1271_FAILVALUE;
    }
}


