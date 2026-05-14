// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @notice TEE verifier interface (from feat/tee gospel).
/// @dev Verifiers return (bool success, bytes32[] identifiers) for multi-attestation support.
interface ITEEVerifier {
    function verify(bytes calldata proof, address pubKey) external view returns (bool success, bytes32[] memory identifiers);
}

/// @notice TEE platform types (from sparsity-xyz RI).
enum TEEType {
    TDX,    // Intel TDX (DCAP quotes, ERC-8004 primary target)
    NITRO   // AWS Nitro Enclaves (PCR-based attestation)
}

/// @title TEERegistryUpgradeable
/// @notice Standalone on-chain registry of TEE-attested keys.
/// @dev Owner-managed verifier list with per-verifier TEEType tags.
///      Permissionless key registration against any approved verifier.
///      Keys can be linked to ERC-8004 agent IDs via IdentityRegistry.
///      ERC-7201 namespaced storage. UUPS upgradeable.
contract TEERegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    // --- Events ---
    event KeyAdded(address indexed pubKey, bytes32 indexed keyHash, bytes32[] identifiers, address verifier, uint256 expiration);
    event KeyLinked(address indexed pubKey, uint256 indexed agentId, bytes32 indexed keyHash);
    event VerifierAdded(address indexed verifier, TEEType teeType);
    event VerifierRemoved(address indexed verifier);

    // --- Structs ---
    struct KeyInfo {
        bytes32[] identifiers;    // platform-specific attestation fields (feat/tee gospel)
        uint256 expiration;
        address verifier;
        bytes pubKeyBytes;        // raw pubKey bytes for non-EVM key types (sparsity RI)
    }

    /// @dev Identity registry address stored at slot 0 (matches MinimalUUPS)
    address private _identityRegistry;

    // --- Storage (ERC-7201) ---

    /// @custom:storage-location erc7201:erc8004.tee.registry
    struct TEERegistryStorage {
        mapping(address => KeyInfo) keys;
        mapping(address => bool) verifiers;
        mapping(bytes32 => address) identifierToKey;
        mapping(address => TEEType) verifierType;    // per-verifier TEE platform (sparsity RI)
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.tee.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TEE_REGISTRY_STORAGE_LOCATION =
        0xd4eaa27091cfd7f09158b30bf0b4be75baf3d13e418ec8691cf1e12ade5e7f00;

    function _getTEERegistryStorage() private pure returns (TEERegistryStorage storage $) {
        assembly {
            $.slot := TEE_REGISTRY_STORAGE_LOCATION
        }
    }

    // --- Init ---

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address identityRegistry_) public reinitializer(2) onlyOwner {
        require(identityRegistry_ != address(0), "bad identity");
        _identityRegistry = identityRegistry_;
    }

    function getIdentityRegistry() external view returns (address) {
        return _identityRegistry;
    }

    // =========================================================================
    // VERIFIER MANAGEMENT (owner only)
    // =========================================================================

    function addVerifier(address v, TEEType teeType) external onlyOwner {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        $.verifiers[v] = true;
        $.verifierType[v] = teeType;
        emit VerifierAdded(v, teeType);
    }

    function removeVerifier(address v) external onlyOwner {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        $.verifiers[v] = false;
        delete $.verifierType[v];
        emit VerifierRemoved(v);
    }

    function isVerifier(address v) external view returns (bool) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        return $.verifiers[v];
    }

    function getVerifierType(address v) external view returns (TEEType) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        return $.verifierType[v];
    }

    // =========================================================================
    // KEY REGISTRATION (permissionless)
    // =========================================================================

    /// @notice Register a new TEE-attested public key.
    /// @param proof TEE attestation proof (DCAP quote, Nitro attestation, etc.)
    /// @param pubKey The public key claimed to be TEE-generated.
    /// @param pubKeyBytes Optional raw public key bytes (for non-EVM key types, sparsity RI).
    /// @param expiration Unix timestamp after which the key is considered expired (0 = never).
    /// @param verifier Approved verifier contract to validate this proof.
    /// @return keyHash Deterministic hash for this key+verifier pair.
    function addKey(bytes calldata proof, address pubKey, bytes calldata pubKeyBytes, uint256 expiration, address verifier) external returns (bytes32 keyHash) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        require($.verifiers[verifier], "unapproved verifier");

        (bool success, bytes32[] memory identifiers) = ITEEVerifier(verifier).verify(proof, pubKey);
        require(success, "invalid TEE proof");

        // Clear old reverse lookups if overwriting
        KeyInfo storage existing = $.keys[pubKey];
        for (uint256 i; i < existing.identifiers.length; i++) {
            delete $.identifierToKey[existing.identifiers[i]];
        }

        // Store key info
        $.keys[pubKey] = KeyInfo(identifiers, expiration, verifier, pubKeyBytes);

        // Set reverse lookups
        for (uint256 i; i < identifiers.length; i++) {
            $.identifierToKey[identifiers[i]] = pubKey;
        }

        keyHash = keccak256(abi.encodePacked(pubKey, verifier));
        emit KeyAdded(pubKey, keyHash, identifiers, verifier, expiration);
    }

    // =========================================================================
    // CONVENIENCE: ONE-SHOT AGENT REGISTRATION (Sparsity RI compatible)
    // =========================================================================

    event AgentRegistered(address indexed pubKey, uint256 indexed agentId, bytes32 keyHash, address verifier);

    /// @notice One-shot TEE agent registration: verify proof, add key, and link to agent ID.
    /// @dev Combines addKey + linkKey in a single transaction. The caller must own agentId.
    ///      Matches Sparsity's registerAgent UX while keeping ERC-8004's two-step architecture.
    function registerAgent(
        bytes calldata proof,
        address pubKey,
        bytes calldata pubKeyBytes,
        uint256 expiration,
        address verifier,
        uint256 agentId
    ) external returns (bytes32 keyHash) {
        // Step 1: addKey (permissionless, anyone can submit a verified key)
        keyHash = this.addKey(proof, pubKey, pubKeyBytes, expiration, verifier);

        // Step 2: linkKey (requires agent ownership)
        // Re-use linkKey logic inline to avoid re-entrancy via external call
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        KeyInfo storage k = $.keys[pubKey];
        require(k.verifier != address(0), "key not found");
        require(k.expiration > block.timestamp || k.expiration == 0, "key expired");
        _requireAgentAuth(agentId);

        emit AgentRegistered(pubKey, agentId, keyHash, verifier);
    }

    // =========================================================================
    // KEY → AGENT LINKING (agent-authorized)
    // =========================================================================

    /// @notice Link a verified TEE key to an ERC-8004 agent identity.
    function linkKey(address pubKey, uint256 agentId) external returns (bytes32 keyHash) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();

        KeyInfo storage k = $.keys[pubKey];
        require(k.verifier != address(0), "key not found");
        require(k.expiration > block.timestamp || k.expiration == 0, "key expired");

        _requireAgentAuth(agentId);

        keyHash = keccak256(abi.encodePacked(pubKey, k.verifier));
        emit KeyLinked(pubKey, agentId, keyHash);
    }

    // =========================================================================
    // READ
    // =========================================================================

    function getKey(address pubKey) external view returns (
        bool valid,
        bytes32[] memory identifiers,
        uint256 expiration,
        address verifier,
        bytes memory pubKeyBytes
    ) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        KeyInfo storage k = $.keys[pubKey];
        if (k.verifier == address(0) || (k.expiration != 0 && k.expiration <= block.timestamp)) {
            return (false, new bytes32[](0), 0, address(0), "");
        }
        return (true, k.identifiers, k.expiration, k.verifier, k.pubKeyBytes);
    }

    function getKeyByIdentifier(bytes32 identifier) external view returns (address pubKey) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        return $.identifierToKey[identifier];
    }

    // =========================================================================
    // INTERNAL
    // =========================================================================

    function _requireAgentAuth(uint256 agentId) private view {
        IIdentityRegistry registry = IIdentityRegistry(_identityRegistry);
        address agentOwner = registry.ownerOf(agentId);
        require(
            msg.sender == agentOwner ||
            registry.isApprovedForAll(agentOwner, msg.sender) ||
            registry.getApproved(agentId) == msg.sender,
            "Not authorized"
        );
    }

    // =========================================================================
    // UPGRADE
    // =========================================================================

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
