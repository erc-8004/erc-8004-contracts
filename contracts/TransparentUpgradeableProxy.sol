// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol" as OZProxy;

// This contract just re-exports OpenZeppelin's TransparentUpgradeableProxy
// so it can be compiled and used in our deployment scripts
contract TransparentUpgradeableProxy is OZProxy.TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address initialOwner,
        bytes memory _data
    ) OZProxy.TransparentUpgradeableProxy(_logic, initialOwner, _data) {}
}
