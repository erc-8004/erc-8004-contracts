// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Create2Factory
 * @notice Simple CREATE2 factory for deploying contracts with deterministic addresses
 */
contract Create2Factory {
    event Deployed(address indexed addr, bytes32 indexed salt);

    /**
     * @notice Deploy a contract using CREATE2
     * @param salt Salt for deterministic address
     * @param bytecode Contract bytecode including constructor args
     * @return addr The deployed contract address
     */
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address addr) {
        assembly {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        emit Deployed(addr, salt);
    }

    /**
     * @notice Compute the address of a contract deployed via CREATE2
     * @param salt Salt used for deployment
     * @param bytecodeHash Keccak256 hash of the bytecode
     * @return addr The computed address
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address addr) {
        addr = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            bytecodeHash
        )))));
    }
}

