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
        // agentId => metadataKey => metadataValue (includes "agentWallet")
        mapping(uint256 => mapping(string => bytes)) _metadata;
        // Metadata reverse lookup: metadataKey => keccak256(metadataValue) => List<agentId>
        mapping(string => mapping(bytes32 => uint256[])) _metadataReverseLookup;
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
    event MetadataReverseLookupSet(uint256 indexed agentId, string indexed metadataKey, bytes metadataValue, address indexed by);

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
        _writeMetadata(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, "", msg.sender);
    }

    function register(string memory agentURI) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _writeMetadata(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, agentURI, msg.sender);
    }

    function register(string memory agentURI, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        agentId = $._lastId++;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _writeMetadata(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, agentURI, msg.sender);

        for (uint256 i; i < metadata.length; i++) {
            require(keccak256(bytes(metadata[i].metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
            _writeMetadata(agentId, metadata[i].metadataKey, metadata[i].metadataValue);
        }
    }

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        return $._metadata[agentId][metadataKey];
    }

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external {
        address agentOwner = _ownerOf(agentId);
        require(
            msg.sender == agentOwner ||
            isApprovedForAll(agentOwner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        require(keccak256(bytes(metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
        _writeMetadata(agentId, metadataKey, metadataValue);
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
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes memory walletData = $._metadata[agentId]["agentWallet"];
        return address(bytes20(walletData));
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

        // Try ECDSA first (EOAs + EIP-7702 delegated EOAs)
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered != newWallet) {
            // ECDSA failed, try ERC1271 (smart contract wallets)
            (bool ok, bytes memory res) = newWallet.staticcall(
                abi.encodeCall(IERC1271.isValidSignature, (digest, signature))
            );
            require(ok && res.length >= 32 && abi.decode(res, (bytes4)) == ERC1271_MAGICVALUE, "invalid wallet sig");
        }

        _writeMetadata(agentId, "agentWallet", abi.encodePacked(newWallet));
    }

    function unsetAgentWallet(uint256 agentId) external {
        address owner = ownerOf(agentId);
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        _writeMetadata(agentId, "agentWallet", "");
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Override _update to clear agentWallet on transfer.
     * This ensures the verified wallet doesn't persist to new owners.
     * Clear BEFORE super._update() to follow Checks-Effects-Interactions pattern.
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // If this is a transfer (not mint), clear agentWallet BEFORE external call
        if (from != address(0) && to != address(0)) {
            _writeMetadata(tokenId, "agentWallet", "");
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @notice Checks if spender is owner or approved for the agent
     * @dev Reverts with ERC721NonexistentToken if agent doesn't exist
     */
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool) {
        address owner = ownerOf(agentId);
        return _isAuthorized(owner, spender, agentId);
    }

    // =========================================================================
    // REVERSE LOOKUP
    // =========================================================================

    /// @notice Generic reverse lookup: find all agent IDs that have metadata[key]=value.
    /// @return agentIds Array of agent IDs matching the query. May be empty.
    function agentByMetadata(string calldata metadataKey, bytes calldata metadataValue)
        external
        view
        returns (uint256[] memory agentIds)
    {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes32 valueHash = keccak256(metadataValue);
        return $._metadataReverseLookup[metadataKey][valueHash];
    }

    /// @notice Unpermissioned write to the reverse lookup index.
    /// Anyone can call this, but it only succeeds if the forward relation exists.
    /// This enables retrofill of old agents without migrating the IdentityRegistry.
    function setReverseLookup(uint256 agentId, string calldata metadataKey, bytes calldata metadataValue) external {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        require(
            keccak256($._metadata[agentId][metadataKey]) == keccak256(metadataValue),
            "forward relation mismatch"
        );
        _addToArray($._metadataReverseLookup[metadataKey][keccak256(metadataValue)], agentId);
        emit MetadataReverseLookupSet(agentId, metadataKey, metadataValue, msg.sender);
    }

    /// @notice Get the owner of agents registered to this wallet. Reverts if agents belong to different owners.
    function getOwnerFromAgentWallet(address wallet) external view returns (address owner) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes32 valueHash = keccak256(abi.encodePacked(wallet));
        uint256[] storage agents = $._metadataReverseLookup["agentWallet"][valueHash];
        require(agents.length > 0, "wallet not found");
        owner = ownerOf(agents[0]);
        for (uint256 i = 1; i < agents.length; i++) {
            require(ownerOf(agents[i]) == owner, "multiple owners");
        }
    }

    // =========================================================================
    // INTERNAL WRITE HELPERS
    // =========================================================================

    /// @dev Single source of truth for metadata writes: keeps forward and reverse in sync, and emits MetadataSet.
    function _writeMetadata(uint256 agentId, string memory key, bytes memory value) private {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes memory oldValue = $._metadata[agentId][key];
        if (oldValue.length > 0) {
            _removeFromArray($._metadataReverseLookup[key][keccak256(oldValue)], agentId);
        }
        if (value.length > 0) {
            uint256[] storage bucket = $._metadataReverseLookup[key][keccak256(value)];
            if (keccak256(bytes(key)) == RESERVED_AGENT_WALLET_KEY_HASH) {
                require(bucket.length == 0, "wallet already assigned");
            }
            _addToArray(bucket, agentId);
        }
        $._metadata[agentId][key] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    function _removeFromArray(uint256[] storage arr, uint256 value) private {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] == value) {
                arr[i] = arr[arr.length - 1];
                arr.pop();
                return;
            }
        }
    }

    function _addToArray(uint256[] storage arr, uint256 value) private {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] == value) return; // no duplicates
        }
        arr.push(value);
    }

    function getVersion() external pure returns (string memory) {
        return "2.1.0";
    }
}
