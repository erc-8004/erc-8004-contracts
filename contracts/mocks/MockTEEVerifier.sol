// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockTEEVerifier {
    bool public shouldPass;
    bytes32[] public returnIdentifiers;

    constructor(bool _shouldPass) {
        shouldPass = _shouldPass;
    }

    function setResult(bool _shouldPass, bytes32[] calldata _identifiers) external {
        shouldPass = _shouldPass;
        delete returnIdentifiers;
        for (uint256 i; i < _identifiers.length; i++) {
            returnIdentifiers.push(_identifiers[i]);
        }
    }

    function verify(bytes calldata, bytes[] calldata) external view returns (bool success, bytes32[] memory identifiers) {
        return (shouldPass, returnIdentifiers);
    }
}
