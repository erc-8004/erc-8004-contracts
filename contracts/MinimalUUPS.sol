// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title MinimalUUPS
 * @dev Minimal UUPS implementation to use as placeholder for vanity proxy addresses
 * This allows proxies to be deployed with vanity addresses before the real implementation is ready
 */
contract MinimalUUPS is OwnableUpgradeable, UUPSUpgradeable {
    address private identityRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _identityRegistry) public initializer {
        __Ownable_init(address(0x547289319C3e6aedB179C0b8e8aF0B5ACd062603));
        __UUPSUpgradeable_init();
        identityRegistry = _identityRegistry;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "0.0.1";
    }
}
