// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IdentityRegistry is ERC721URIStorage, Ownable {
    uint256 private _lastId = 0;

    // agentId => key => value
    mapping(uint256 => mapping(string => string)) private _metadata;

    struct MetadataEntry {
        string metadataKey;
        string metadataValue;
    }

    event Registered(uint256 indexed agentId, string agentUri, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, string metadataValue);
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
            _metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }
    }

    function getMetadata(uint256 agentId, string memory key) external view returns (string memory) {
        return _metadata[agentId][key];
    }

    function setMetadata(uint256 agentId, string memory key, string memory value) external {
        require(
            msg.sender == _ownerOf(agentId) ||
            isApprovedForAll(_ownerOf(agentId), msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _metadata[agentId][key] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    function setAgentUri(uint256 agentId, string calldata newUri) external {
        require(
            msg.sender == _ownerOf(agentId) ||
            isApprovedForAll(_ownerOf(agentId), msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _setTokenURI(agentId, newUri);
        emit UriUpdated(agentId, newUri, msg.sender);
    }
}

