// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IIdentityRegistry.sol";

/**
 * @title ValidationRegistryUpgradeable
 * @notice Registry for managing validation requests and responses for AI agents
 * @dev Implements UUPS upgradeable pattern with validator whitelist for trusted validations
 */
contract ValidationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    address private identityRegistry;

    // Whitelist of trusted validators
    mapping(address => bool) private _trustedValidators;

    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string requestUri,
        bytes32 indexed requestHash
    );

    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8 response,
        string responseUri,
        bytes32 responseHash,
        bytes32 tag
    );

    event ValidatorWhitelisted(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    /**
     * @notice Represents the status of a validation request
     * @dev hasResponded distinguishes between pending (false) and completed with score 0 (true)
     * @param validatorAddress Address of the validator assigned to this request
     * @param agentId ID of the agent being validated
     * @param response Validation score (0-100), only valid when hasResponded is true
     * @param responseHash Hash of the validation response data for integrity verification
     * @param tag Category or type tag for filtering validations
     * @param lastUpdate Timestamp of the last update
     * @param hasResponded True if validator has submitted a response, false if still pending
     */
    struct ValidationStatus {
        address validatorAddress;
        uint256 agentId;
        uint8 response;       // 0..100
        bytes32 responseHash;
        bytes32 tag;
        uint256 lastUpdate;
        bool hasResponded;    // Distinguishes pending from zero-score responses
    }

    // Combined key (agentId + requestHash) => validation status
    // This prevents different agents from preempting each other's requestHashes
    mapping(uint256 => mapping(bytes32 => ValidationStatus)) public validations;

    // agentId => list of requestHashes
    mapping(uint256 => bytes32[]) private _agentValidations;

    // validatorAddress => list of requestHashes
    mapping(address => bytes32[]) private _validatorRequests;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _identityRegistry) public initializer {
        require(_identityRegistry != address(0), "bad identity");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        identityRegistry = _identityRegistry;
    }

    function setIdentityRegistry(address _identityRegistry) external onlyOwner {
        require(_identityRegistry != address(0), "bad identity");
        identityRegistry = _identityRegistry;
    }

    function getIdentityRegistry() external view returns (address) {
        return identityRegistry;
    }

    /**
     * @notice Adds a validator to the trusted whitelist
     * @dev Only contract owner can add trusted validators
     * @param validator Address of the validator to whitelist
     */
    function addTrustedValidator(address validator) external onlyOwner {
        require(validator != address(0), "Invalid validator");
        _trustedValidators[validator] = true;
        emit ValidatorWhitelisted(validator);
    }

    /**
     * @notice Removes a validator from the trusted whitelist
     * @dev Only contract owner can remove trusted validators
     * @param validator Address of the validator to remove
     */
    function removeTrustedValidator(address validator) external onlyOwner {
        _trustedValidators[validator] = false;
        emit ValidatorRemoved(validator);
    }

    /**
     * @notice Checks if a validator is trusted
     * @param validator Address to check
     * @return True if the validator is whitelisted
     */
    function isTrustedValidator(address validator) external view returns (bool) {
        return _trustedValidators[validator];
    }

    /**
     * @notice Submits a validation request for an agent
     * @dev Caller must be agent owner or approved operator. Validator must be whitelisted.
     * @param validatorAddress Address of the trusted validator to handle this request
     * @param agentId ID of the agent to be validated
     * @param requestUri URI containing the validation request details
     * @param requestHash Hash of the request data for integrity verification
     */
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestUri,
        bytes32 requestHash
    ) external {
        require(validatorAddress != address(0), "bad validator");
        require(_trustedValidators[validatorAddress], "Validator not whitelisted");

        // Check request uniqueness per agent (prevents preemption by other agents)
        require(validations[agentId][requestHash].validatorAddress == address(0), "exists");

        // Check permission: caller must be owner, approved operator, or approved for this token
        IIdentityRegistry registry = IIdentityRegistry(identityRegistry);
        address owner = registry.ownerOf(agentId);
        require(
            msg.sender == owner ||
            registry.isApprovedForAll(owner, msg.sender) ||
            registry.getApproved(agentId) == msg.sender,
            "Not authorized"
        );

        validations[agentId][requestHash] = ValidationStatus({
            validatorAddress: validatorAddress,
            agentId: agentId,
            response: 0,
            responseHash: bytes32(0),
            tag: bytes32(0),
            lastUpdate: block.timestamp,
            hasResponded: false
        });

        // Track for lookups
        _agentValidations[agentId].push(requestHash);
        _validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestUri, requestHash);
    }

    /**
     * @notice Submits a validation response (can only be called once per request)
     * @dev Only the designated validator can respond, and only once
     * @param agentId ID of the agent being validated
     * @param requestHash Hash identifying the validation request
     * @param response Validation score (0-100)
     * @param responseUri URI containing the detailed validation response
     * @param responseHash Hash of the response data for integrity verification
     * @param tag Category or type tag for this validation
     */
    function validationResponse(
        uint256 agentId,
        bytes32 requestHash,
        uint8 response,
        string calldata responseUri,
        bytes32 responseHash,
        bytes32 tag
    ) external {
        ValidationStatus storage s = validations[agentId][requestHash];
        require(s.validatorAddress != address(0), "unknown");
        require(msg.sender == s.validatorAddress, "not validator");
        require(!s.hasResponded, "Already responded");
        require(response <= 100, "resp>100");

        s.response = response;
        s.responseHash = responseHash;
        s.tag = tag;
        s.lastUpdate = block.timestamp;
        s.hasResponded = true;

        emit ValidationResponse(s.validatorAddress, s.agentId, requestHash, response, responseUri, responseHash, tag);
    }

    /**
     * @notice Retrieves the status of a validation request
     * @param agentId ID of the agent
     * @param requestHash Hash identifying the request
     * @return validatorAddress Address of the assigned validator
     * @return agentId_ ID of the agent being validated
     * @return response Validation score (only valid if hasResponded is true)
     * @return responseHash Hash of the response data
     * @return tag Category tag for this validation
     * @return lastUpdate Timestamp of last update
     * @return hasResponded Whether the validator has responded
     */
    function getValidationStatus(uint256 agentId, bytes32 requestHash)
        external
        view
        returns (
            address validatorAddress,
            uint256 agentId_,
            uint8 response,
            bytes32 responseHash,
            bytes32 tag,
            uint256 lastUpdate,
            bool hasResponded
        )
    {
        ValidationStatus memory s = validations[agentId][requestHash];
        require(s.validatorAddress != address(0), "unknown");
        return (s.validatorAddress, s.agentId, s.response, s.responseHash, s.tag, s.lastUpdate, s.hasResponded);
    }

    /**
     * @notice Calculates summary statistics for an agent's validations
     * @dev Only counts validations that have received responses (hasResponded == true)
     * @dev Average uses integer division which truncates decimals (e.g., 152/3 = 50, not 50.67)
     * @param agentId ID of the agent
     * @param validatorAddresses Optional filter for specific validators (empty = all)
     * @param tag Optional filter for specific tag (bytes32(0) = all)
     * @return count Number of completed validations matching the filters
     * @return avgResponse Average validation score (truncated to uint8)
     */
    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        bytes32 tag
    ) external view returns (uint64 count, uint8 avgResponse) {
        uint256 totalResponse = 0;
        count = 0;

        bytes32[] storage requestHashes = _agentValidations[agentId];

        for (uint256 i = 0; i < requestHashes.length; i++) {
            ValidationStatus storage s = validations[agentId][requestHashes[i]];

            // Only count validations that have been responded to
            if (!s.hasResponded) continue;

            // Filter by validator if specified
            bool matchValidator = (validatorAddresses.length == 0);
            if (!matchValidator) {
                for (uint256 j = 0; j < validatorAddresses.length; j++) {
                    if (s.validatorAddress == validatorAddresses[j]) {
                        matchValidator = true;
                        break;
                    }
                }
            }

            // Filter by tag (0x0 means no filter)
            bool matchTag = (tag == bytes32(0)) || (s.tag == tag);

            if (matchValidator && matchTag) {
                totalResponse += s.response;
                count++;
            }
        }

        avgResponse = count > 0 ? uint8(totalResponse / count) : 0;
    }

    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory) {
        return _agentValidations[agentId];
    }

    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory) {
        return _validatorRequests[validatorAddress];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "1.0.0";
    }
}
