// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IdentityRegistry is ERC721URIStorage, Ownable {
    uint256 private _lastId = 0;

    // agentId => key => value
    mapping(uint256 => mapping(string => bytes)) private _metadata;

    // agentId => array of keys
    mapping(uint256 => string[]) private _metadataKeys;

    // agentId => key => index in _metadataKeys array (plus 1, 0 means not exists)
    mapping(uint256 => mapping(string => uint256)) private _metadataKeyIndex;

    struct MetadataEntry {
        string key;
        bytes value;
    }

    event Registered(uint256 indexed agentId, string tokenURI, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedKey, string key, bytes value);
    event UriUpdated(uint256 indexed agentId, string newUri, address indexed updatedBy);

    constructor() ERC721("AgentIdentity", "AID") Ownable(msg.sender) {}

    function register() external returns (uint256 agentId) {
        agentId = _lastId++;
        _safeMint(msg.sender, agentId);
        emit Registered(agentId, "", msg.sender);
    }

    function register(string memory tokenUri) external returns (uint256 agentId) {
        agentId = _lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, tokenUri);
        emit Registered(agentId, tokenUri, msg.sender);
    }

    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        agentId = _lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, tokenUri);
        emit Registered(agentId, tokenUri, msg.sender);

        for (uint256 i = 0; i < metadata.length; i++) {
            _setMetadataInternal(agentId, metadata[i].key, metadata[i].value);
            emit MetadataSet(agentId, metadata[i].key, metadata[i].key, metadata[i].value);
        }
    }

    function _setMetadataInternal(uint256 agentId, string memory key, bytes memory value) private {
        // If key doesn't exist yet, add it to the keys array
        if (_metadataKeyIndex[agentId][key] == 0) {
            _metadataKeys[agentId].push(key);
            _metadataKeyIndex[agentId][key] = _metadataKeys[agentId].length;
        }
        _metadata[agentId][key] = value;
    }

    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory) {
        return _metadata[agentId][key];
    }

    function setMetadata(uint256 agentId, string memory key, bytes memory value) external {
        require(
            msg.sender == _ownerOf(agentId) ||
            isApprovedForAll(_ownerOf(agentId), msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _setMetadataInternal(agentId, key, value);
        emit MetadataSet(agentId, key, key, value);
    }

    function getAllMetadataKeys(uint256 agentId) external view returns (string[] memory) {
        return _metadataKeys[agentId];
    }

    function getAllMetadata(uint256 agentId) external view returns (MetadataEntry[] memory) {
        string[] memory keys = _metadataKeys[agentId];
        MetadataEntry[] memory entries = new MetadataEntry[](keys.length);

        for (uint256 i = 0; i < keys.length; i++) {
            entries[i] = MetadataEntry({
                key: keys[i],
                value: _metadata[agentId][keys[i]]
            });
        }

        return entries;
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
}

