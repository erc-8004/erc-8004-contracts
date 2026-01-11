// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract IdentityRegistryUpgradeable is
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    EIP712Upgradeable
{
    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    /// @custom:storage-location erc7201:erc8004.identity.registry
    struct IdentityRegistryStorage {
        uint256 _lastId;
        // agentId => metadataKey => metadataValue
        mapping(uint256 => mapping(string => bytes)) _metadata;
        // agentId => verified agent wallet (address-typed convenience)
        mapping(uint256 => address) _agentWallet;
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.identity.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant IDENTITY_REGISTRY_STORAGE_LOCATION =
        0xa040f782729de4970518741823ec1276cbcd41a0c7493f62d173341566a04e00;

    function _getIdentityRegistryStorage() private pure returns (IdentityRegistryStorage storage $) {
        assembly {
            $.slot := IDENTITY_REGISTRY_STORAGE_LOCATION
        }
    }

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);

    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;
    uint256 private constant MAX_DEADLINE_DELAY = 5 minutes;
    bytes32 private constant RESERVED_AGENT_WALLET_KEY_HASH = keccak256("agentWallet");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public reinitializer(2) onlyOwner {
        __ERC721_init("AgentIdentity", "AGENT");
        __ERC721URIStorage_init();
        __EIP712_init("ERC8004IdentityRegistry", "1");
    }

    function register() external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        $._agentWallet[agentId] = msg.sender;
        emit Registered(agentId, "", msg.sender);
    }

    function register(string memory agentURI) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        $._agentWallet[agentId] = msg.sender;
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);
    }

    function register(string memory agentURI, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        $._agentWallet[agentId] = msg.sender;
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);

        for (uint256 i = 0; i < metadata.length; i++) {
            require(keccak256(bytes(metadata[i].metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
            $._metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }
    }

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        return $._metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external {
        require(
            msg.sender == _ownerOf(agentId) ||
            isApprovedForAll(_ownerOf(agentId), msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        require(keccak256(bytes(metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        address owner = ownerOf(agentId);
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        // Ensure token exists (consistent with other identity reads)
        ownerOf(agentId);
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        return $._agentWallet[agentId];
    }

    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external {
        address owner = ownerOf(agentId);
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        require(newWallet != address(0), "bad wallet");
        require(block.timestamp <= deadline, "expired");
        require(deadline <= block.timestamp + MAX_DEADLINE_DELAY, "deadline too far");

        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, owner, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (newWallet.code.length == 0) {
            address recovered = ECDSA.recover(digest, signature);
            require(recovered == newWallet, "invalid wallet sig");
        } else {
            bytes4 result = IERC1271(newWallet).isValidSignature(digest, signature);
            require(result == ERC1271_MAGICVALUE, "invalid wallet sig");
        }

        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._agentWallet[agentId] = newWallet;

        // Also store as reserved metadata for discoverability/indexers.
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(newWallet);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Override _update to clear agentWallet on transfer.
     * This ensures the verified wallet doesn't persist to new owners.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Call parent implementation
        address result = super._update(to, tokenId, auth);

        // If this is a transfer (not mint), clear agentWallet
        if (from != address(0) && to != address(0)) {
            IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
            $._agentWallet[tokenId] = address(0);
            $._metadata[tokenId]["agentWallet"] = "";
            emit MetadataSet(tokenId, "agentWallet", "agentWallet", "");
        }

        return result;
    }

    function getVersion() external pure returns (string memory) {
        return "1.1.0";
    }
}
