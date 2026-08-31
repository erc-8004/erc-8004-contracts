// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "../../contracts/ERC1967Proxy.sol";
import {HardhatMinimalUUPS} from "../../contracts/HardhatMinimalUUPS.sol";
import {IdentityRegistryUpgradeable} from "../../contracts/IdentityRegistryUpgradeable.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistryUpgradeable private registry;
    address private agentOwner;

    function setUp() public {
        agentOwner = makeAddr("agentOwner");

        HardhatMinimalUUPS placeholder = new HardhatMinimalUUPS();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(placeholder), abi.encodeCall(HardhatMinimalUUPS.initialize, (address(0))));
        IdentityRegistryUpgradeable implementation = new IdentityRegistryUpgradeable();

        HardhatMinimalUUPS(address(proxy))
            .upgradeToAndCall(address(implementation), abi.encodeCall(IdentityRegistryUpgradeable.initialize, ()));
        registry = IdentityRegistryUpgradeable(address(proxy));
    }

    function testFuzz_RegisterStoresUri(string calldata agentUri) public {
        vm.prank(agentOwner);
        uint256 agentId = registry.register(agentUri);

        assertEq(registry.ownerOf(agentId), agentOwner);
        assertEq(registry.tokenURI(agentId), agentUri);
        assertEq(registry.getAgentWallet(agentId), agentOwner);
    }
}
