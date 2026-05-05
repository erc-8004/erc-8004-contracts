// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface ITEEVerifier {
    function verify(bytes calldata proof, address pubKey) external view returns (bool success, bytes32[] memory identifiers);
}

contract ValidationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    // --- Events: general validation ---
    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string requestURI,
        bytes32 indexed requestHash
    );

    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8 response,
        string responseURI,
        bytes32 responseHash,
        string tag
    );

    // --- Events: TEE ---
    event KeyAdded(address indexed pubKey, bytes32 indexed keyHash, bytes32[] identifiers, address verifier, uint256 expiration);
    event KeyLinked(address indexed pubKey, uint256 indexed agentId, bytes32 indexed keyHash);
    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);

    // --- Structs ---
    struct ValidationStatus {
        address validatorAddress;
        uint256 agentId;
        uint8 response;       // 0..100
        bytes32 responseHash;
        string tag;
        uint256 lastUpdate;
        bool hasResponse;
    }

    struct KeyInfo {
        bytes32[] identifiers;
        uint256 expiration;
        address verifier;
    }

    /// @dev Identity registry address stored at slot 0 (matches MinimalUUPS)
    address private _identityRegistry;

    // --- Storage: general validation (ERC-7201) ---

    /// @custom:storage-location erc7201:erc8004.validation.registry
    struct ValidationRegistryStorage {
        mapping(bytes32 => ValidationStatus) validations;
        mapping(uint256 => bytes32[]) _agentValidations;
        mapping(address => bytes32[]) _validatorRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.validation.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VALIDATION_REGISTRY_STORAGE_LOCATION =
        0x21543a2dd0df813994fbf82c69c61d1aafcdce183d68d2ef40068bdce1481100;

    function _getValidationRegistryStorage() private pure returns (ValidationRegistryStorage storage $) {
        assembly {
            $.slot := VALIDATION_REGISTRY_STORAGE_LOCATION
        }
    }

    // --- Storage: TEE (ERC-7201) ---

    /// @custom:storage-location erc7201:erc8004.tee.registry
    struct TEERegistryStorage {
        mapping(address => KeyInfo) keys;
        mapping(address => bool) verifiers;
        mapping(bytes32 => address) identifierToKey;
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
    // GENERAL VALIDATION
    // =========================================================================

    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestHash
    ) external {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        require(validatorAddress != address(0), "bad validator");
        require($.validations[requestHash].validatorAddress == address(0), "exists");

        _requireAgentAuth(agentId);

        $.validations[requestHash] = ValidationStatus({
            validatorAddress: validatorAddress,
            agentId: agentId,
            response: 0,
            responseHash: bytes32(0),
            tag: "",
            lastUpdate: block.timestamp,
            hasResponse: false
        });

        $._agentValidations[agentId].push(requestHash);
        $._validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }

    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) external {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        ValidationStatus storage s = $.validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        require(msg.sender == s.validatorAddress, "not validator");
        require(response <= 100, "resp>100");
        s.response = response;
        s.responseHash = responseHash;
        s.tag = tag;
        s.lastUpdate = block.timestamp;
        s.hasResponse = true;
        emit ValidationResponse(s.validatorAddress, s.agentId, requestHash, response, responseURI, responseHash, tag);
    }

    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, string memory tag, uint256 lastUpdate)
    {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        ValidationStatus memory s = $.validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        return (s.validatorAddress, s.agentId, s.response, s.responseHash, s.tag, s.lastUpdate);
    }

    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        string calldata tag
    ) external view returns (uint64 count, uint8 avgResponse) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        uint256 totalResponse;

        bytes32[] storage requestHashes = $._agentValidations[agentId];

        for (uint256 i; i < requestHashes.length; i++) {
            ValidationStatus storage s = $.validations[requestHashes[i]];

            bool matchValidator = (validatorAddresses.length == 0);
            if (!matchValidator) {
                for (uint256 j; j < validatorAddresses.length; j++) {
                    if (s.validatorAddress == validatorAddresses[j]) {
                        matchValidator = true;
                        break;
                    }
                }
            }

            bool matchTag = (bytes(tag).length == 0) || (keccak256(bytes(s.tag)) == keccak256(bytes(tag)));

            if (matchValidator && matchTag && s.hasResponse) {
                totalResponse += s.response;
                count++;
            }
        }

        avgResponse = count > 0 ? uint8(totalResponse / count) : 0;
    }

    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        return $._agentValidations[agentId];
    }

    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        return $._validatorRequests[validatorAddress];
    }

    // =========================================================================
    // TEE KEY REGISTRY
    // =========================================================================

    // --- Verifier management (owner only) ---

    function addVerifier(address v) external onlyOwner {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        $.verifiers[v] = true;
        emit VerifierAdded(v);
    }

    function removeVerifier(address v) external onlyOwner {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        $.verifiers[v] = false;
        emit VerifierRemoved(v);
    }

    function isVerifier(address v) external view returns (bool) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        return $.verifiers[v];
    }

    // --- Key registration (permissionless) ---

    function addKey(bytes calldata proof, address pubKey, uint256 expiration, address verifier) external returns (bytes32 keyHash) {
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
        $.keys[pubKey] = KeyInfo(identifiers, expiration, verifier);

        // Set reverse lookups
        for (uint256 i; i < identifiers.length; i++) {
            $.identifierToKey[identifiers[i]] = pubKey;
        }

        keyHash = keccak256(abi.encodePacked(pubKey, verifier));
        emit KeyAdded(pubKey, keyHash, identifiers, verifier, expiration);
    }

    // --- Link key to agent (agent-authorized) ---

    function linkKey(address pubKey, uint256 agentId) external {
        TEERegistryStorage storage tee = _getTEERegistryStorage();
        ValidationRegistryStorage storage val = _getValidationRegistryStorage();

        // Key must exist and not be expired
        KeyInfo storage k = tee.keys[pubKey];
        require(k.verifier != address(0), "key not found");
        require(k.expiration > block.timestamp, "key expired");

        // Caller must be authorized for this agent
        _requireAgentAuth(agentId);

        // Deterministic hash for this key+agent link
        bytes32 keyHash = keccak256(abi.encodePacked(pubKey, k.verifier));

        // Write into validation storage so it shows up in getSummary/getAgentValidations
        require(val.validations[keyHash].validatorAddress == address(0), "already linked");

        val.validations[keyHash] = ValidationStatus({
            validatorAddress: k.verifier,
            agentId: agentId,
            response: 100,
            responseHash: keccak256(abi.encodePacked(k.identifiers)),
            tag: "tee",
            lastUpdate: block.timestamp,
            hasResponse: true
        });

        val._agentValidations[agentId].push(keyHash);
        val._validatorRequests[k.verifier].push(keyHash);

        emit KeyLinked(pubKey, agentId, keyHash);
    }

    // --- Read keys ---

    function getKey(address pubKey) external view returns (bool valid, bytes32[] memory identifiers, uint256 expiration, address verifier) {
        TEERegistryStorage storage $ = _getTEERegistryStorage();
        KeyInfo storage k = $.keys[pubKey];
        if (k.verifier == address(0) || k.expiration <= block.timestamp) {
            return (false, new bytes32[](0), 0, address(0));
        }
        return (true, k.identifiers, k.expiration, k.verifier);
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
        return "3.0.0";
    }
}
