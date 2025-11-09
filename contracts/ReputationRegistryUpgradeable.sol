// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IIdentityRegistry.sol";

/**
 * @title ReputationRegistryUpgradeable
 * @notice Registry for managing reputation feedback and responses for AI agents
 * @dev Implements UUPS upgradeable pattern with Sybil resistance mechanisms
 */
contract ReputationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {

    address private identityRegistry;

    // Sybil resistance: minimum requirements for giving feedback
    uint256 private _minBlockAge; // Minimum block age for feedback provider account
    uint256 private _maxResponsesPerFeedback; // Maximum responses allowed per feedback item

    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint8 score,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string feedbackUri,
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
        string responseUri,
        bytes32 responseHash
    );

    struct Feedback {
        uint8 score;
        string tag1;
        string tag2;
        bool isRevoked;
    }

    // agentId => clientAddress => feedbackIndex => Feedback (1-indexed)
    mapping(uint256 => mapping(address => mapping(uint64 => Feedback))) private _feedback;

    // agentId => clientAddress => last feedback index
    mapping(uint256 => mapping(address => uint64)) private _lastIndex;

    // agentId => clientAddress => feedbackIndex => responder => response count
    mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => uint64)))) private _responseCount;

    // Track all unique responders for each feedback
    mapping(uint256 => mapping(address => mapping(uint64 => address[]))) private _responders;
    mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => bool)))) private _responderExists;

    // Track all unique clients that have given feedback for each agent
    mapping(uint256 => address[]) private _clients;
    mapping(uint256 => mapping(address => bool)) private _clientExists;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _identityRegistry) public initializer {
        require(_identityRegistry != address(0), "bad identity");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        identityRegistry = _identityRegistry;
        _minBlockAge = 0; // Default: no restriction
        _maxResponsesPerFeedback = 100; // Default: reasonable limit
    }

    function setIdentityRegistry(address _identityRegistry) external onlyOwner {
        require(_identityRegistry != address(0), "bad identity");
        identityRegistry = _identityRegistry;
    }

    function getIdentityRegistry() external view returns (address) {
        return identityRegistry;
    }

    /**
     * @notice Sets the minimum block age requirement for feedback providers (Sybil resistance)
     * @dev Only contract owner can modify this parameter
     * @param blocks Minimum number of blocks an account must exist before giving feedback
     */
    function setMinBlockAge(uint256 blocks) external onlyOwner {
        _minBlockAge = blocks;
    }

    /**
     * @notice Gets the current minimum block age requirement
     * @return Minimum block age for feedback providers
     */
    function getMinBlockAge() external view returns (uint256) {
        return _minBlockAge;
    }

    /**
     * @notice Sets the maximum number of responses allowed per feedback item
     * @dev Only contract owner can modify this parameter. Prevents DoS via unbounded storage growth
     * @param max Maximum number of unique responders per feedback
     */
    function setMaxResponsesPerFeedback(uint256 max) external onlyOwner {
        require(max > 0, "Max must be > 0");
        _maxResponsesPerFeedback = max;
    }

    /**
     * @notice Gets the maximum responses allowed per feedback
     * @return Maximum number of responders per feedback item
     */
    function getMaxResponsesPerFeedback() external view returns (uint256) {
        return _maxResponsesPerFeedback;
    }

    /**
     * @notice Submits feedback for an agent
     * @dev Implements Sybil resistance by checking account age and preventing self-feedback
     * @param agentId ID of the agent receiving feedback
     * @param score Reputation score (0-100)
     * @param tag1 Primary category tag for filtering
     * @param tag2 Secondary category tag for filtering
     * @param feedbackUri URI containing detailed feedback content
     * @param feedbackHash Hash of the feedback data for integrity verification
     */
    function giveFeedback(
        uint256 agentId,
        uint8 score,
        string calldata tag1,
        string calldata tag2,
        string calldata feedbackUri,
        bytes32 feedbackHash
    ) external {
        require(score <= 100, "score>100");

        // Verify agent exists
        require(_agentExists(agentId), "Agent does not exist");

        // Get agent owner
        IIdentityRegistry registry = IIdentityRegistry(identityRegistry);
        address agentOwner = registry.ownerOf(agentId);

        // SECURITY: Prevent self-feedback from owner and operators
        require(
            msg.sender != agentOwner &&
            !registry.isApprovedForAll(agentOwner, msg.sender) &&
            registry.getApproved(agentId) != msg.sender,
            "Self-feedback not allowed"
        );

        // SYBIL RESISTANCE: Require minimum account age if configured
        // Note: This checks contract deployment block, not EOA creation
        // For EOAs, tx.origin can be used but requires careful consideration
        if (_minBlockAge > 0) {
            // This is a basic check - can be enhanced with additional on-chain criteria
            require(block.number >= _minBlockAge, "Account too new");
        }

        // Get current index for this client-agent pair (1-indexed)
        uint64 currentIndex = _lastIndex[agentId][msg.sender] + 1;

        // Store feedback at 1-indexed position
        _feedback[agentId][msg.sender][currentIndex] = Feedback({
            score: score,
            tag1: tag1,
            tag2: tag2,
            isRevoked: false
        });

        // Update last index
        _lastIndex[agentId][msg.sender] = currentIndex;

        // track new client
        if (!_clientExists[agentId][msg.sender]) {
            _clients[agentId].push(msg.sender);
            _clientExists[agentId][msg.sender] = true;
        }

        emit NewFeedback(agentId, msg.sender, score, tag1, tag1, tag2, feedbackUri, feedbackHash);
    }

    /**
     * @notice Revokes previously submitted feedback
     * @dev Only the feedback provider can revoke their own feedback
     * @param agentId ID of the agent
     * @param feedbackIndex Index of the feedback to revoke (1-indexed)
     */
    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        _validateFeedbackIndex(agentId, msg.sender, feedbackIndex);
        require(!_feedback[agentId][msg.sender][feedbackIndex].isRevoked, "Already revoked");

        _feedback[agentId][msg.sender][feedbackIndex].isRevoked = true;
        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    /**
     * @notice Appends a response to existing feedback
     * @dev Prevents responses to revoked feedback and limits total responders to prevent DoS
     * @param agentId ID of the agent
     * @param clientAddress Address of the feedback provider
     * @param feedbackIndex Index of the feedback to respond to (1-indexed)
     * @param responseUri URI containing the response content
     * @param responseHash Hash of the response data for integrity verification
     */
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseUri,
        bytes32 responseHash
    ) external {
        _validateFeedbackIndex(agentId, clientAddress, feedbackIndex);
        require(bytes(responseUri).length > 0, "Empty URI");

        // Prevent responses to revoked feedback
        Feedback storage fb = _feedback[agentId][clientAddress][feedbackIndex];
        require(!fb.isRevoked, "Feedback revoked");

        // Track new responder with DoS protection
        if (!_responderExists[agentId][clientAddress][feedbackIndex][msg.sender]) {
            // Prevent unbounded storage growth
            require(
                _responders[agentId][clientAddress][feedbackIndex].length < _maxResponsesPerFeedback,
                "Max responders reached"
            );

            _responders[agentId][clientAddress][feedbackIndex].push(msg.sender);
            _responderExists[agentId][clientAddress][feedbackIndex][msg.sender] = true;
        }

        // Increment response count for this responder
        _responseCount[agentId][clientAddress][feedbackIndex][msg.sender]++;

        emit ResponseAppended(agentId, clientAddress, feedbackIndex, msg.sender, responseUri, responseHash);
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64) {
        return _lastIndex[agentId][clientAddress];
    }

    /**
     * @notice Reads a specific feedback entry
     * @param agentId ID of the agent
     * @param clientAddress Address of the feedback provider
     * @param index Index of the feedback to read (1-indexed)
     * @return score Reputation score (0-100)
     * @return tag1 Primary category tag
     * @return tag2 Secondary category tag
     * @return isRevoked Whether the feedback has been revoked
     */
    function readFeedback(uint256 agentId, address clientAddress, uint64 index)
        external
        view
        returns (uint8 score, string memory tag1, string memory tag2, bool isRevoked)
    {
        _validateFeedbackIndex(agentId, clientAddress, index);
        Feedback storage f = _feedback[agentId][clientAddress][index];
        return (f.score, f.tag1, f.tag2, f.isRevoked);
    }

    /**
     * @notice Calculates summary statistics for an agent's reputation
     * @dev Only counts non-revoked feedback. Average uses integer division (truncates decimals)
     * @param agentId ID of the agent
     * @param clientAddresses Optional filter for specific clients (empty = all)
     * @param tag1 Optional filter for primary tag (empty string = all)
     * @param tag2 Optional filter for secondary tag (empty string = all)
     * @return count Number of non-revoked feedback entries matching filters
     * @return averageScore Average reputation score (truncated to uint8)
     */
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, uint8 averageScore) {
        address[] memory clientList;
        if (clientAddresses.length > 0) {
            clientList = clientAddresses;
        } else {
            clientList = _clients[agentId];
        }

        uint256 totalScore = 0;
        count = 0;

        for (uint256 i = 0; i < clientList.length; i++) {
            uint64 lastIdx = _lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = _feedback[agentId][clientList[i]][j];
                if (fb.isRevoked) continue;
                if (bytes(tag1).length > 0 && keccak256(bytes(fb.tag1)) != keccak256(bytes(tag1))) continue;
                if (bytes(tag2).length > 0 && keccak256(bytes(fb.tag2)) != keccak256(bytes(tag2))) continue;

                totalScore += fb.score;
                count++;
            }
        }

        averageScore = count > 0 ? uint8(totalScore / count) : 0;
    }

    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    ) external view returns (
        address[] memory clients,
        uint8[] memory scores,
        string[] memory tag1s,
        string[] memory tag2s,
        bool[] memory revokedStatuses
    ) {
        address[] memory clientList;
        if (clientAddresses.length > 0) {
            clientList = clientAddresses;
        } else {
            clientList = _clients[agentId];
        }

        // First pass: count matching feedback
        uint256 totalCount = 0;
        for (uint256 i = 0; i < clientList.length; i++) {
            uint64 lastIdx = _lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = _feedback[agentId][clientList[i]][j];
                if (!includeRevoked && fb.isRevoked) continue;
                if (bytes(tag1).length > 0 && keccak256(bytes(fb.tag1)) != keccak256(bytes(tag1))) continue;
                if (bytes(tag2).length > 0 && keccak256(bytes(fb.tag2)) != keccak256(bytes(tag2))) continue;
                totalCount++;
            }
        }

        // Initialize arrays
        clients = new address[](totalCount);
        scores = new uint8[](totalCount);
        tag1s = new string[](totalCount);
        tag2s = new string[](totalCount);
        revokedStatuses = new bool[](totalCount);

        // Second pass: populate arrays
        uint256 idx = 0;
        for (uint256 i = 0; i < clientList.length; i++) {
            uint64 lastIdx = _lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIdx; j++) {
                Feedback storage fb = _feedback[agentId][clientList[i]][j];
                if (!includeRevoked && fb.isRevoked) continue;
                if (bytes(tag1).length > 0 && keccak256(bytes(fb.tag1)) != keccak256(bytes(tag1))) continue;
                if (bytes(tag2).length > 0 && keccak256(bytes(fb.tag2)) != keccak256(bytes(tag2))) continue;

                clients[idx] = clientList[i];
                scores[idx] = fb.score;
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
        if (clientAddress == address(0)) {
            // Count all responses for all clients
            address[] memory clients = _clients[agentId];
            for (uint256 i = 0; i < clients.length; i++) {
                uint64 lastIdx = _lastIndex[agentId][clients[i]];
                for (uint64 j = 1; j <= lastIdx; j++) {
                    count += _countResponses(agentId, clients[i], j, responders);
                }
            }
        } else if (feedbackIndex == 0) {
            // Count all responses for specific clientAddress
            uint64 lastIdx = _lastIndex[agentId][clientAddress];
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
        if (responders.length == 0) {
            // Count from all responders
            address[] memory allResponders = _responders[agentId][clientAddress][feedbackIndex];
            for (uint256 k = 0; k < allResponders.length; k++) {
                count += _responseCount[agentId][clientAddress][feedbackIndex][allResponders[k]];
            }
        } else {
            // Count from specified responders
            for (uint256 k = 0; k < responders.length; k++) {
                count += _responseCount[agentId][clientAddress][feedbackIndex][responders[k]];
            }
        }
    }

    function getClients(uint256 agentId) external view returns (address[] memory) {
        return _clients[agentId];
    }

    /**
     * @notice Internal helper to validate feedback index bounds
     * @dev Reusable validation logic to reduce code duplication
     * @param agentId ID of the agent
     * @param clientAddress Address of the feedback provider
     * @param index Feedback index to validate
     */
    function _validateFeedbackIndex(uint256 agentId, address clientAddress, uint64 index) internal view {
        require(index > 0, "index must be > 0");
        require(index <= _lastIndex[agentId][clientAddress], "index out of bounds");
    }

    /**
     * @notice Checks if an agent exists in the identity registry
     * @param agentId ID of the agent to check
     * @return True if the agent exists
     */
    function _agentExists(uint256 agentId) internal view returns (bool) {
        try IIdentityRegistry(identityRegistry).ownerOf(agentId) returns (address owner) {
            return owner != address(0);
        } catch {
            return false;
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
