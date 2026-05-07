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
        // Reverse lookup: metadataKey => keccak256(metadataValue) => List<agentId>
        mapping(string => mapping(bytes32 => uint256[])) _reverseLookup;
        // For agentWallet "1 or fail": wallet => owner
        mapping(address => address) _agentWalletOwner;
        // True if multiple different owners have agents registered to this wallet
        mapping(address => bool) _agentWalletMultipleOwners;
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
    event ReverseLookupSet(uint256 indexed agentId, string indexed metadataKey, bytes metadataValue, address indexed by);
    event AgentWalletOwnerConflict(address indexed wallet, address ownerA, address ownerB);

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
        _enforceAgentWalletUnique(msg.sender, 0);
        $._agentWalletOwner[msg.sender] = msg.sender;
        agentId = $._lastId++;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _safeMint(msg.sender, agentId);
        _addToReverseLookup(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, "", msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));
    }

    function register(string memory agentURI) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        _enforceAgentWalletUnique(msg.sender, 0);
        $._agentWalletOwner[msg.sender] = msg.sender;
        agentId = $._lastId++;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _addToReverseLookup(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, agentURI, msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));
    }

    function register(string memory agentURI, MetadataEntry[] memory metadata) external returns (uint256 agentId) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        _enforceAgentWalletUnique(msg.sender, 0);
        $._agentWalletOwner[msg.sender] = msg.sender;
        agentId = $._lastId++;
        $._metadata[agentId]["agentWallet"] = abi.encodePacked(msg.sender);
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);
        _addToReverseLookup(agentId, "agentWallet", abi.encodePacked(msg.sender));
        emit Registered(agentId, agentURI, msg.sender);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(msg.sender));

        for (uint256 i; i < metadata.length; i++) {
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
        address agentOwner = _ownerOf(agentId);
        require(
            msg.sender == agentOwner ||
            isApprovedForAll(agentOwner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );
        require(keccak256(bytes(metadataKey)) != RESERVED_AGENT_WALLET_KEY_HASH, "reserved key");
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();

        // Remove old value from reverse lookup if it existed
        bytes memory oldValue = $._metadata[agentId][metadataKey];
        if (oldValue.length > 0) {
            _removeFromReverseLookup(agentId, metadataKey, oldValue);
        }

        // If new value is non-empty, add to reverse lookup
        if (metadataValue.length > 0) {
            _addToReverseLookup(agentId, metadataKey, metadataValue);
        }

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

        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();

        _enforceAgentWalletUnique(newWallet, agentId);

        // Clear old wallet from reverse lookup
        bytes memory oldWallet = $._metadata[agentId]["agentWallet"];
        if (oldWallet.length > 0) {
            _removeFromReverseLookup(agentId, "agentWallet", oldWallet);
        }

        // Update owner tracking
        $._agentWalletOwner[newWallet] = owner;

        $._metadata[agentId]["agentWallet"] = abi.encodePacked(newWallet);
        _addToReverseLookup(agentId, "agentWallet", abi.encodePacked(newWallet));
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));
    }

    function unsetAgentWallet(uint256 agentId) external {
        address owner = ownerOf(agentId);
        require(
            msg.sender == owner ||
            isApprovedForAll(owner, msg.sender) ||
            msg.sender == getApproved(agentId),
            "Not authorized"
        );

        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();

        // Clear from reverse lookup and owner tracking
        bytes memory oldWallet = $._metadata[agentId]["agentWallet"];
        if (oldWallet.length > 0) {
            _removeFromReverseLookup(agentId, "agentWallet", oldWallet);
            $._agentWalletOwner[address(bytes20(oldWallet))] = address(0);
        }

        $._metadata[agentId]["agentWallet"] = "";
        emit MetadataSet(agentId, "agentWallet", "agentWallet", "");
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
            IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
            bytes memory oldWallet = $._metadata[tokenId]["agentWallet"];
            if (oldWallet.length > 0) {
                _removeFromReverseLookup(tokenId, "agentWallet", oldWallet);
                $._agentWalletOwner[address(bytes20(oldWallet))] = address(0);
            }
            $._metadata[tokenId]["agentWallet"] = "";
            emit MetadataSet(tokenId, "agentWallet", "agentWallet", "");
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
        return $._reverseLookup[metadataKey][valueHash];
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
        // Remove any old value this agent has for this key from the reverse lookup
        bytes memory oldValue = $._metadata[agentId][metadataKey];
        if (oldValue.length > 0) {
            bytes32 oldHash = keccak256(oldValue);
            if (oldHash != keccak256(metadataValue)) {
                _removeFromArray($._reverseLookup[metadataKey][oldHash], agentId);
            }
        }
        _addToArray($._reverseLookup[metadataKey][keccak256(metadataValue)], agentId);

        // For agentWallet specifically: update owner tracking
        if (keccak256(bytes(metadataKey)) == RESERVED_AGENT_WALLET_KEY_HASH) {
            address owner = _ownerOf(agentId);
            address wallet = address(bytes20(metadataValue));
            _setAgentWalletOwner(wallet, owner);
        }

        emit ReverseLookupSet(agentId, metadataKey, metadataValue, msg.sender);
    }

    /// @notice Get the owner of an agent wallet. Reverts if multiple different owners
    /// have agents with this wallet (Chainlink's "1 or fail" requirement).
    function getOwnerFromAgentWallet(address wallet) external view returns (address owner) {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        require(!$._agentWalletMultipleOwners[wallet], "multiple owners");
        owner = $._agentWalletOwner[wallet];
        require(owner != address(0), "wallet not found");
    }

    // =========================================================================
    // INTERNAL REVERSE LOOKUP HELPERS
    // =========================================================================

    function _addToReverseLookup(uint256 agentId, string memory key, bytes memory value) private {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes32 valueHash = keccak256(value);
        // Don't add duplicates
        uint256[] storage list = $._reverseLookup[key][valueHash];
        for (uint256 i; i < list.length; i++) {
            if (list[i] == agentId) return;
        }
        list.push(agentId);
    }

    function _removeFromReverseLookup(uint256 agentId, string memory key, bytes memory value) private {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        bytes32 valueHash = keccak256(value);
        _removeFromArray($._reverseLookup[key][valueHash], agentId);
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

    function _enforceAgentWalletUnique(address wallet, uint256 excludeAgentId) private view {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        // If multiple owners exist for this wallet, reject
        if ($._agentWalletMultipleOwners[wallet]) {
            revert("wallet has multiple owners");
        }
        // If wallet is unowned, allow
        address existingOwner = $._agentWalletOwner[wallet];
        if (existingOwner == address(0)) return;
        // If wallet is owned by calling agent's owner, allow
        if (excludeAgentId != 0) {
            address agentOwner = _ownerOf(excludeAgentId);
            if (existingOwner == agentOwner) return;
        }
        // Otherwise, reject as non-unique
        revert("wallet not unique");
    }

    function _setAgentWalletOwner(address wallet, address owner) private {
        IdentityRegistryStorage storage $ = _getIdentityRegistryStorage();
        address existing = $._agentWalletOwner[wallet];
        if (existing == address(0)) {
            // First registrant
            $._agentWalletOwner[wallet] = owner;
        } else if (existing != owner) {
            // Conflict: different owners, mark as multiple
            $._agentWalletMultipleOwners[wallet] = true;
            emit AgentWalletOwnerConflict(wallet, existing, owner);
        }
        // If same owner, no-op
    }

    function getVersion() external pure returns (string memory) {
        return "2.1.0";
    }
}
