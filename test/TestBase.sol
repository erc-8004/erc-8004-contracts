// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MinimalUUPSTest} from "./MinimalUUPSTest.sol";
import {IdentityRegistryUpgradeable} from "../contracts/IdentityRegistryUpgradeable.sol";
import {ReputationRegistryUpgradeable} from "../contracts/ReputationRegistryUpgradeable.sol";
import {ValidationRegistryUpgradeable} from "../contracts/ValidationRegistryUpgradeable.sol";

/**
 * @title TestBase
 * @dev Base test contract that deploys and configures all ERC-8004 registries.
 *      Mirrors actual deployment flow: MinimalUUPS placeholder -> upgrade to real implementations.
 *      Test contract (address(this)) becomes owner of all registries.
 */
contract TestBase is Test {
    // Deployed contract instances (proxies cast to implementation types)
    IdentityRegistryUpgradeable public identityRegistry;
    ReputationRegistryUpgradeable public reputationRegistry;
    ValidationRegistryUpgradeable public validationRegistry;

    // Proxy addresses (for direct proxy interactions if needed)
    address public identityRegistryProxy;
    address public reputationRegistryProxy;
    address public validationRegistryProxy;

    // Implementation addresses
    address public minimalUUPSImpl;
    address public identityRegistryImpl;
    address public reputationRegistryImpl;
    address public validationRegistryImpl;

    // Test accounts
    address public owner;
    address public alice;
    address public bob;
    address public charlie;
    address public malicious;

    // Storage slot for _identityRegistry (slot 0 in ReputationRegistry and ValidationRegistry)
    uint256 private constant IDENTITY_REGISTRY_SLOT = 0;

    function setUp() public virtual {
        // Setup test accounts
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        malicious = makeAddr("malicious");

        // ============================================================
        // PHASE 1: Deploy MinimalUUPSTest placeholder implementation
        // ============================================================
        minimalUUPSImpl = address(new MinimalUUPSTest());

        // ============================================================
        // PHASE 2: Deploy proxies pointing to MinimalUUPSTest
        // ============================================================

        // Deploy IdentityRegistry proxy (initialize with zero address - doesn't need identityRegistry)
        bytes memory identityInitData = abi.encodeCall(
            MinimalUUPSTest.initialize,
            (address(0))
        );
        identityRegistryProxy = address(new ERC1967Proxy(minimalUUPSImpl, identityInitData));

        // Deploy ReputationRegistry proxy (initialize with identityRegistry address)
        bytes memory reputationInitData = abi.encodeCall(
            MinimalUUPSTest.initialize,
            (identityRegistryProxy)
        );
        reputationRegistryProxy = address(new ERC1967Proxy(minimalUUPSImpl, reputationInitData));

        // Deploy ValidationRegistry proxy (initialize with identityRegistry address)
        bytes memory validationInitData = abi.encodeCall(
            MinimalUUPSTest.initialize,
            (identityRegistryProxy)
        );
        validationRegistryProxy = address(new ERC1967Proxy(minimalUUPSImpl, validationInitData));

        // ============================================================
        // PHASE 3: Deploy real implementations
        // ============================================================
        identityRegistryImpl = address(new IdentityRegistryUpgradeable());
        reputationRegistryImpl = address(new ReputationRegistryUpgradeable());
        validationRegistryImpl = address(new ValidationRegistryUpgradeable());

        // ============================================================
        // PHASE 4: Upgrade proxies to real implementations
        // ============================================================

        // Upgrade IdentityRegistry
        bytes memory identityUpgradeData = abi.encodeCall(
            IdentityRegistryUpgradeable.initialize,
            ()
        );
        MinimalUUPSTest(identityRegistryProxy).upgradeToAndCall(
            identityRegistryImpl,
            identityUpgradeData
        );

        // Upgrade ReputationRegistry
        bytes memory reputationUpgradeData = abi.encodeCall(
            ReputationRegistryUpgradeable.initialize,
            (identityRegistryProxy)
        );
        MinimalUUPSTest(reputationRegistryProxy).upgradeToAndCall(
            reputationRegistryImpl,
            reputationUpgradeData
        );

        // Upgrade ValidationRegistry
        bytes memory validationUpgradeData = abi.encodeCall(
            ValidationRegistryUpgradeable.initialize,
            (identityRegistryProxy)
        );
        MinimalUUPSTest(validationRegistryProxy).upgradeToAndCall(
            validationRegistryImpl,
            validationUpgradeData
        );

        // ============================================================
        // PHASE 5: Cast proxies to implementation types for convenience
        // ============================================================
        identityRegistry = IdentityRegistryUpgradeable(identityRegistryProxy);
        reputationRegistry = ReputationRegistryUpgradeable(reputationRegistryProxy);
        validationRegistry = ValidationRegistryUpgradeable(validationRegistryProxy);
    }

    // ============================================================
    // Setup verification test
    // ============================================================

    function test_setUp() public view {
        // Verify ownership
        assertEq(identityRegistry.owner(), owner, "IdentityRegistry owner mismatch");
        assertEq(reputationRegistry.owner(), owner, "ReputationRegistry owner mismatch");
        assertEq(validationRegistry.owner(), owner, "ValidationRegistry owner mismatch");

        // Verify identity registry references (read private slot 0)
        address reputationIdentityRef = address(uint160(uint256(
            vm.load(reputationRegistryProxy, bytes32(IDENTITY_REGISTRY_SLOT))
        )));
        address validationIdentityRef = address(uint160(uint256(
            vm.load(validationRegistryProxy, bytes32(IDENTITY_REGISTRY_SLOT))
        )));

        assertEq(reputationIdentityRef, identityRegistryProxy, "ReputationRegistry identityRegistry mismatch");
        assertEq(validationIdentityRef, identityRegistryProxy, "ValidationRegistry identityRegistry mismatch");

        // Verify versions
        assertEq(identityRegistry.getVersion(), "1.1.0", "IdentityRegistry version mismatch");
        assertEq(reputationRegistry.getVersion(), "1.1.0", "ReputationRegistry version mismatch");
        assertEq(validationRegistry.getVersion(), "1.1.0", "ValidationRegistry version mismatch");

        // Verify ERC721 initialization
        assertEq(identityRegistry.name(), "AgentIdentity", "ERC721 name mismatch");
        assertEq(identityRegistry.symbol(), "AGENT", "ERC721 symbol mismatch");
    }

    // ============================================================
    // Helper functions for tests
    // ============================================================

    /// @dev Register an agent and return its agentId
    function _registerAgent(address caller) internal returns (uint256 agentId) {
        vm.prank(caller);
        agentId = identityRegistry.register();
    }

    /// @dev Register an agent with URI and return its agentId
    function _registerAgentWithURI(address caller, string memory uri) internal returns (uint256 agentId) {
        vm.prank(caller);
        agentId = identityRegistry.register(uri);
    }

    /// @dev Register an agent with URI and metadata, return its agentId
    function _registerAgentWithMetadata(
        address caller,
        string memory uri,
        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata
    ) internal returns (uint256 agentId) {
        vm.prank(caller);
        agentId = identityRegistry.register(uri, metadata);
    }

    /// @dev Give feedback to an agent
    function _giveFeedback(
        address caller,
        uint256 agentId,
        uint8 score,
        string memory tag1,
        string memory tag2
    ) internal {
        vm.prank(caller);
        reputationRegistry.giveFeedback(agentId, score, tag1, tag2, "", "", bytes32(0));
    }

    /// @dev Request validation for an agent
    function _requestValidation(
        address caller,
        uint256 agentId,
        address validator,
        bytes32 requestHash
    ) internal {
        vm.prank(caller);
        validationRegistry.validationRequest(validator, agentId, "", requestHash);
    }

    /// @dev Respond to a validation request
    function _respondValidation(
        address validator,
        bytes32 requestHash,
        uint8 response
    ) internal {
        vm.prank(validator);
        validationRegistry.validationResponse(requestHash, response, "", bytes32(0), "");
    }
}