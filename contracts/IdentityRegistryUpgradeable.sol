// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract IdentityRegistryUpgradeable is
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    struct MetadataEntry {
        string metadataKey;
        string metadataValue;
    }

    /// @custom:storage-location erc7201:erc8004.identity.registry
    struct IdentityRegistryStorage {
        uint256 _lastId;
        // agentId => metadataKey => metadataValue
        mapping(uint256 => mapping(string => string)) _metadata;
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.identity.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant IDENTITY_REGISTRY_STORAGE_LOCATION =
        0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00;

    function _getIdentityRegistryStorage() private pure returns (IdentityRegistryStorage storage $) {
        assembly {
            $.slot := IDENTITY_REGISTRY_STORAGE_LOCATION
        }
    }

    event Registered(uint256 indexed agentId, string agentUri, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, string metadataValue);
    event UriUpdated(uint256 indexed agentId, string newUri, address indexed updatedBy);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC721_init("AgentIdentity", "AGENT");
        __ERC721URIStorage_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._lastId = 0;
    }

    function register() external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        emit Registered(agentId, "", msg.sender);
    }

    function register(string memory agentUri) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentUri);
        emit Registered(agentId, agentUri, msg.sender);
    }

    function register(string memory agentUri, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentUri);
        emit Registered(agentId, agentUri, msg.sender);

        for (uint256 i = 0; i < metadata.length; i++) {
            $._metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }
    }

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (string memory) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        return $._metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, string memory metadataValue) external {
        require(
            msg.sender == _ownerOf(agentId) ||
            isApprovedForAll(_ownerOf(agentId), msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    function setAgentUri(uint256 agentId, string calldata newUri) external {
        address owner = ownerOf(agentId);
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _setTokenURI(agentId, newUri);
        emit UriUpdated(agentId, newUri, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "1.1.0";
    }
}
