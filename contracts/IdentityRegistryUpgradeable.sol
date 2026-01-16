// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract IdentityRegistryUpgradeable is
    ERC721URIStorageUpgradeable,
    Ownable2StepUpgradeable,
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
        mapping(uint256 agentId => mapping(string metadataKey => bytes metadataValue)) _metadata;
        mapping(uint256 agentId => address verifiedWallet) _agentWallet;
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

        $._agentWallet[agentId] = msg.sender;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        emit Registered(agentId, "", msg.sender);

        _safeMint(msg.sender, agentId);
    }

    function register(string memory agentURI) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        
        $._agentWallet[agentId] = msg.sender;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);

        _safeMint(msg.sender, agentId);
    }

    function register(string memory agentURI, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        
        $._agentWallet[agentId] = msg.sender;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _setTokenURI(agentId, agentURI);
        emit Registered(agentId, agentURI, msg.sender);

        for (uint256 i; i < metadata.length; i++) {
            require(keccak256(bytes(metadata[i].metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
            $._metadata[agentId][metadata[i].metadataKey] = metadata[i].metadataValue;
            emit MetadataSet(agentId, metadata[i].metadataKey, metadata[i].metadataKey, metadata[i].metadataValue);
        }

        _safeMint(msg.sender, agentId);
    }

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory output) {
        output = _getIdentityRegistryStorage()._metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external {
        _onlyOwnerOrOperator(agentId);

        require(keccak256(bytes(metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._metadata[agentId][metadataKey] = metadataValue;
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);
    }

    function setAgentURI(uint256 agentId, string calldata newURI) external {
        _onlyOwnerOrOperator(agentId);
        _setTokenURI(agentId, newURI);
        emit URIUpdated(agentId, newURI, msg.sender);
    }

    function getAgentWallet(uint256 agentId) external view returns (address wallet) {
        // Ensure token exists (consistent with other identity reads)
        ownerOf(agentId);
        wallet = _getIdentityRegistryStorage()._agentWallet[agentId];
    }

    function setAgentWallet(
        uint256 agentId,
        address newWallet,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(newWallet != address(0), "bad wallet");
        require(block.timestamp <= deadline, "expired");
        require(deadline <= block.timestamp + MAX_DEADLINE_DELAY, "deadline too far");

        address agentOwner = _onlyOwnerOrOperator(agentId);

        bytes32 structHash = keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, newWallet, agentOwner, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        // for ERC1271 uses a staticcall so storage updates afterwards are safer
        require(SignatureChecker.isValidSignatureNow(newWallet, digest, signature), "invalid wallet sig");

        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        $._agentWallet[agentId] = newWallet;

        // Also store as reserved metadata for discoverability/indexers.
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(newWallet);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));
    }

    function _onlyOwnerOrOperator(uint256 agentId) internal view returns(address nftOwner) {
        // enforces nft existence & ownership
        nftOwner = ownerOf(agentId);

        require(
            msg.sender == nftOwner ||
            isApprovedForAll(nftOwner, msg.sender) ||
            msg.sender == _getApproved(agentId),
            "Not authorized"
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Override _update to clear agentWallet on transfer.
     * This ensures the verified wallet doesn't persist to new owners.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address result) {
        address from = _ownerOf(tokenId);

        // Call parent implementation
        result = super._update(to, tokenId, auth);

        // If this is a transfer to a different user (not self-transfer or mint/burn), clear agentWallet
        if (from != address(0) && to != address(0) && from != to) {
            IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
            $._agentWallet[tokenId] = address(0);
            $._metadata[tokenId]["agentWallet"] = "";
            emit MetadataSet(tokenId, "agentWallet", "agentWallet", "");
        }
    }

    function getVersion() external pure returns (string memory) {
        return "1.1.0";
    }
}
