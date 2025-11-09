// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title IdentityRegistryUpgradeable
 * @notice NFT-based registry for AI agent identities with metadata storage
 * @dev Implements UUPS upgradeable pattern. Each agent is represented as an ERC721 token
 */
contract IdentityRegistryUpgradeable is
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    uint256 private _lastId;

    // agentId => key => value
    mapping(uint256 => mapping(string => string)) private _metadata;

    struct MetadataEntry {
        string metadataKey;
        string metadataValue;
    }

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, string metadataValue);
    event UriUpdated(uint256 indexed agentId, string newUri, address indexed updatedBy);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("AgentIdentity", "AID");
        __ERC721URIStorage_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        // _lastId = 0 is redundant - uint256 defaults to 0
    }

    /**
     * @notice Registers a new agent identity (minimal version)
     * @dev Follows CEI pattern - all state updates before external calls
     * @return agentId The ID of the newly registered agent
     */
    function register() external returns (uint256 agentId) {
        agentId = _lastId++;
        // CEI: State updates complete, now external call
        _safeMint(msg.sender, agentId);
        emit Registered(agentId, "", msg.sender);
    }

    /**
     * @notice Registers a new agent identity with a token URI
     * @dev Follows CEI pattern - all state updates before external calls
     * @param tokenUri URI pointing to agent metadata (JSON)
     * @return agentId The ID of the newly registered agent
     */
    function register(string memory tokenUri) external returns (uint256 agentId) {
        agentId = _lastId++;
        _setTokenURI(agentId, tokenUri);
        // CEI: State updates complete, now external call
        _safeMint(msg.sender, agentId);
        emit Registered(agentId, tokenUri, msg.sender);
    }

    /**
     * @notice Registers a new agent identity with token URI and metadata
     * @dev Follows CEI pattern - all state updates before external calls
     * @param tokenUri URI pointing to agent metadata (JSON)
     * @param metadata Array of key-value pairs for on-chain metadata
     * @return agentId The ID of the newly registered agent
     */
    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        agentId = _lastId++;
        _setTokenURI(agentId, tokenUri);

        // Set metadata before minting (CEI pattern)
        for (uint256 i = 0; i < metadata.length; i++) {
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }

        // CEI: All state updates complete, now external call
        _safeMint(msg.sender, agentId);
        emit Registered(agentId, tokenUri, msg.sender);
    }

    /**
     * @notice Retrieves metadata value for a given key
     * @param agentId ID of the agent
     * @param metadataKey Key to look up
     * @return Metadata value associated with the key
     */
    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (string memory) {
        return _metadata[agentId][metadataKey];
    }

    /**
     * @notice Sets metadata for an agent
     * @dev Caller must be owner, approved operator, or approved for this specific token
     * @param agentId ID of the agent
     * @param metadataKey Key to set
     * @param metadataValue Value to store
     */
    function setMetadata(uint256 agentId, string memory metadataKey, string memory metadataValue) external {
        _requireAuthorized(agentId);
        _metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    /**
     * @notice Updates the token URI for an agent
     * @dev Caller must be owner, approved operator, or approved for this specific token
     * @param agentId ID of the agent
     * @param newUri New URI pointing to agent metadata
     */
    function setAgentUri(uint256 agentId, string calldata newUri) external {
        _requireAuthorized(agentId);
        _setTokenURI(agentId, newUri);
        emit UriUpdated(agentId, newUri, msg.sender);
    }

    /**
     * @notice Internal helper to check authorization for agent operations
     * @dev Reverts if caller is not owner, approved operator, or approved for the token
     * @dev Uses ownerOf() consistently for error handling
     * @param agentId ID of the agent to check authorization for
     */
    function _requireAuthorized(uint256 agentId) internal view {
        address owner = ownerOf(agentId); // Will revert if token doesn't exist
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
