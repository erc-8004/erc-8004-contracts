// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title Singleton Factory (EIP-2470)
 * @notice Exposes CREATE2 (EIP-1014) to deploy bytecode on deterministic addresses based on initialization code and salt.
 * @author Ricardo Guilherme Schmidt (Status Research & Development GmbH)
 *
 * @dev This contract is included for ABI purposes only.
 * The SAFE Singleton Factory is already deployed at 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
 * on all major EVM chains. Use that address instead of deploying a new factory.
 * See: https://github.com/safe-global/safe-singleton-factory
 */
contract SingletonFactory {
    /**
     * @notice Deploys `_initCode` using `_salt` for defining the deterministic address.
     * @param _initCode Initialization code.
     * @param _salt Arbitrary value to modify resulting address.
     * @return createdContract Created contract address.
     */
    function deploy(bytes memory _initCode, bytes32 _salt)
        public
        returns (address payable createdContract)
    {
        assembly {
            createdContract := create2(0, add(_initCode, 0x20), mload(_initCode), _salt)
        }
        require(createdContract != address(0), "Deploy failed");
    }
}
