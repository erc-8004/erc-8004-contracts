// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IIdentityRegistry {
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool);
}

contract ReputationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {

    int128 private constant MAX_ABS_VALUE = 1e38;

    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );

    event FeedbackRevoked(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 indexed feedbackIndex
    );

    event ResponseAppended(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        address indexed responder,
        string responseURI,
        bytes32 responseHash
    );

    struct Feedback {
        int128 value;          // 16 bytes
        uint8 valueDecimals;   // 1 byte  (packed with value + isRevoked)
        bool isRevoked;        // 1 byte  (packed with value + valueDecimals)
        string tag1;
        string tag2;
    }

    /// @dev Identity registry address stored at slot 0 (matches MinimalUUPS)
    address private _identityRegistry;

    /// @custom:storage-location erc7201:erc8004.reputation.registry
    struct ReputationRegistryStorage {
        // agentId => clientAddress => feedbackIndex => Feedback (1-indexed)
        mapping(uint256 => mapping(address => mapping(uint64 => Feedback))) _feedback;
        // agentId => clientAddress => last feedback index
        mapping(uint256 => mapping(address => uint64)) _lastIndex;
        // agentId => clientAddress => feedbackIndex => responder => response count
        mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => uint64)))) _responseCount;
        // Track all unique responders for each feedback
        mapping(uint256 => mapping(address => mapping(uint64 => address[]))) _responders;
        mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => bool)))) _responderExists;
        // Track all unique clients that have given feedback for each agent
        mapping(uint256 => address[]) _clients;
        mapping(uint256 => mapping(address => bool)) _clientExists;
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.reputation.registry.2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REPUTATION_REGISTRY_STORAGE_LOCATION =
        0xa03d7693f2b3746b2d03f163c788147b71aa82854399a21fdf4de143ba778300;

    function _getReputationRegistryStorage() private pure returns (ReputationRegistryStorage storage $) {
        assembly {
            $.slot := REPUTATION_REGISTRY_STORAGE_LOCATION
        }
    }

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

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        require(valueDecimals <= 18, "too many decimals");
        require(value >= -MAX_ABS_VALUE && value <= MAX_ABS_VALUE, "value too large");

        // SECURITY: Prevent self-feedback from owner and operators
        // Also reverts with ERC721NonexistentToken if agent doesn't exist
        require(!IIdentityRegistry(_identityRegistry).isAuthorizedOrOwner(msg.sender, agentId), "Self-feedback not allowed");

        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();

        // Increment and get current index (1-indexed)
        uint64 currentIndex = ++$._lastIndex[agentId][msg.sender];

        // Store feedback
        $._feedback[agentId][msg.sender][currentIndex] = Feedback({
            value: value,
            valueDecimals: valueDecimals,
            tag1: tag1,
            tag2: tag2,
            isRevoked: false
        });

        // track new client
        if (!$._clientExists[agentId][msg.sender]) {
            $._clients[agentId].push(msg.sender);
            $._clientExists[agentId][msg.sender] = true;
        }

        emit NewFeedback(agentId, msg.sender, currentIndex, value, valueDecimals, tag1, tag1, tag2, endpoint, feedbackURI, feedbackHash);
    }

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        require(feedbackIndex > 0, "index must be > 0");
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        require(feedbackIndex <= $._lastIndex[agentId][msg.sender], "index out of bounds");
        require(!$._feedback[agentId][msg.sender][feedbackIndex].isRevoked, "Already revoked");

        $._feedback[agentId][msg.sender][feedbackIndex].isRevoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        require(feedbackIndex > 0, "index must be > 0");
        require(bytes(responseURI).length > 0, "Empty URI");
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        require(feedbackIndex <= $._lastIndex[agentId][clientAddress], "index out of bounds");

        // Track new responder
        if (!$._responderExists[agentId][clientAddress][feedbackIndex][msg.sender]) {
            $._responders[agentId][clientAddress][feedbackIndex].push(msg.sender);
            $._responderExists[agentId][clientAddress][feedbackIndex][msg.sender] = true;
        }

        // Increment response count for this responder
        $._responseCount[agentId][clientAddress][feedbackIndex][msg.sender]++;

        emit ResponseAppended(agentId, clientAddress, feedbackIndex, msg.sender, responseURI, responseHash);
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64) {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        return $._lastIndex[agentId][clientAddress];
    }

    function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex)
        external
        view
        returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked)
    {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        require(feedbackIndex > 0, "index must be > 0");
        require(feedbackIndex <= $._lastIndex[agentId][clientAddress], "index out of bounds");
        Feedback storage f = $._feedback[agentId][clientAddress][feedbackIndex];
        return (f.value, f.valueDecimals, f.tag1, f.tag2, f.isRevoked);
    }

    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals) {

        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        address[] memory clientList;
        if (clientAddresses.length > 0) {
            clientList = clientAddresses;
        } else {
            revert("clientAddresses required");
        }

        bytes32 emptyHash = keccak256(bytes(""));
        bytes32 tag1Hash = keccak256(bytes(tag1));
        bytes32 tag2Hash = keccak256(bytes(tag2));

        // WAD: 18 decimal fixed-point precision for internal math
        int256 sum;

        // Track frequency of each valueDecimals (0-18, anything >18 treated as 18)
        uint64[19] memory decimalCounts;

        for (uint256 i; i < clientList.length; i++) {
            uint64 lastIdx = $._lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = $._feedback[agentId][clientList[i]][j];
                if (fb.isRevoked) continue;
                if (emptyHash != tag1Hash &&
                    tag1Hash != keccak256(bytes(fb.tag1))) continue;
                if (emptyHash != tag2Hash &&
                    tag2Hash != keccak256(bytes(fb.tag2))) continue;

                // Normalize to 18 decimals (WAD)
                // `valueDecimals` is bounded to <= 18 on write; keep math signed.
                int256 factor = int256(10 ** uint256(18 - fb.valueDecimals));
                int256 normalized = fb.value * factor;
                decimalCounts[fb.valueDecimals]++;

                sum += normalized;
                count++;
            }
        }

        if (count == 0) {
            return (0, 0, 0);
        }

        // Find mode (most frequent valueDecimals)
        uint8 modeDecimals;
        uint64 maxCount;
        for (uint8 d; d <= 18; d++) {
            if (decimalCounts[d] > maxCount) {
                maxCount = decimalCounts[d];
                modeDecimals = d;
            }
        }

        // Calculate average in WAD, then scale to mode precision
        int256 avgWad = sum / int256(uint256(count));
        summaryValue = int128(avgWad / int256(10 ** uint256(18 - modeDecimals)));
        summaryValueDecimals = modeDecimals;
    }

    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    ) external view returns (
        address[] memory clients,
        uint64[] memory feedbackIndexes,
        int128[] memory values,
        uint8[] memory valueDecimals,
        string[] memory tag1s,
        string[] memory tag2s,
        bool[] memory revokedStatuses
    ) {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        address[] memory clientList;
        if (clientAddresses.length > 0) {
            clientList = clientAddresses;
        } else {
            clientList = $._clients[agentId];
        }

        // First pass: count matching feedback
        bytes32 emptyHash = keccak256(bytes(""));
        bytes32 tag1Hash = keccak256(bytes(tag1));
        bytes32 tag2Hash = keccak256(bytes(tag2));
        uint256 totalCount;
        for (uint256 i; i < clientList.length; i++) {
            uint64 lastIdx = $._lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = $._feedback[agentId][clientList[i]][j];
                if (!includeRevoked && fb.isRevoked) continue;
                if (emptyHash != tag1Hash &&
                    tag1Hash != keccak256(bytes(fb.tag1))) continue;
                if (emptyHash != tag2Hash &&
                    tag2Hash != keccak256(bytes(fb.tag2))) continue;
                totalCount++;
            }
        }

        // Initialize arrays
        clients = new address[](totalCount);
        feedbackIndexes = new uint64[](totalCount);
        values = new int128[](totalCount);
        valueDecimals = new uint8[](totalCount);
        tag1s = new string[](totalCount);
        tag2s = new string[](totalCount);
        revokedStatuses = new bool[](totalCount);

        // Second pass: populate arrays
        uint256 idx;
        for (uint256 i; i < clientList.length; i++) {
            uint64 lastIdx = $._lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = $._feedback[agentId][clientList[i]][j];
                if (!includeRevoked && fb.isRevoked) continue;
                if (emptyHash != tag1Hash &&
                    tag1Hash != keccak256(bytes(fb.tag1))) continue;
                if (emptyHash != tag2Hash &&
                    tag2Hash != keccak256(bytes(fb.tag2))) continue;

                clients[idx] = clientList[i];
                feedbackIndexes[idx] = j;
                values[idx] = fb.value;
                valueDecimals[idx] = fb.valueDecimals;
                tag1s[idx] = fb.tag1;
                tag2s[idx] = fb.tag2;
                revokedStatuses[idx] = fb.isRevoked;
                idx++;
            }
        }
    }

    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) external view returns (uint64 count) {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        if (clientAddress == address(0)) {
            // Count all responses for all clients
            address[] memory clients = $._clients[agentId];
            for (uint256 i; i < clients.length; i++) {
                uint64 lastIdx = $._lastIndex[agentId][clients[i]];
                for (uint64 j = 1; j <= lastIdx; j++) {
                    count += _countResponses(agentId, clients[i], j, responders);
                }
            }
        } else if (feedbackIndex == 0) {
            // Count all responses for specific clientAddress
            uint64 lastIdx = $._lastIndex[agentId][clientAddress];
            for (uint64 j = 1; j <= lastIdx; j++) {
                count += _countResponses(agentId, clientAddress, j, responders);
            }
        } else {
            // Count responses for specific clientAddress and feedbackIndex
            count = _countResponses(agentId, clientAddress, feedbackIndex, responders);
        }
    }

    function _countResponses(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) internal view returns (uint64 count) {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        if (responders.length == 0) {
            // Count from all responders
            address[] memory allResponders = $._responders[agentId][clientAddress][feedbackIndex];
            for (uint256 k; k < allResponders.length; k++) {
                count += $._responseCount[agentId][clientAddress][feedbackIndex][allResponders[k]];
            }
        } else {
            // Count from specified responders
            for (uint256 k; k < responders.length; k++) {
                count += $._responseCount[agentId][clientAddress][feedbackIndex][responders[k]];
            }
        }
    }

    function getClients(uint256 agentId) external view returns (address[] memory) {
        ReputationRegistryStorage storage $ = _getReputationRegistryStorage();
        return $._clients[agentId];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "2.0.0";
    }
}
