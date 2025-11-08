// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
}

/// @notice Minimal, compilable scaffold of ERC-8004 Validation Registry.
/// - Stores identityRegistry address
/// - Allows requests & responses, emits events
contract ValidationRegistry {
    address private immutable identityRegistry;

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

    struct ValidationStatus {
        address validatorAddress;
        uint256 agentId;
        uint8 response;       // 0..100
        bytes32 responseHash;
        bytes32 tag;
        uint256 lastUpdate;
    }

    // requestHash => validation status
    mapping(bytes32 => ValidationStatus) public validations;

    // agentId => list of requestHashes
    mapping(uint256 => bytes32[]) private _agentValidations;

    // validatorAddress => list of requestHashes
    mapping(address => bytes32[]) private _validatorRequests;

    constructor(address _identityRegistry) {
        require(_identityRegistry != address(0), "bad identity");
        identityRegistry = _identityRegistry;
    }

    function getIdentityRegistry() external view returns (address) {
        return identityRegistry;
    }

    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestUri,
        bytes32 requestHash
    ) external {
        require(validatorAddress != address(0), "bad validator");
        require(validations[requestHash].validatorAddress == address(0), "exists");

        // Check permission: caller must be owner or approved operator
        IIdentityRegistry registry = IIdentityRegistry(identityRegistry);
        address owner = registry.ownerOf(agentId);
        require(
            msg.sender == owner || 
            registry.isApprovedForAll(owner, msg.sender) ||
            registry.getApproved(agentId) == msg.sender,
            "Not authorized"
        );

        validations[requestHash] = ValidationStatus({
            validatorAddress: validatorAddress,
            agentId: agentId,
            response: 0,
            responseHash: bytes32(0),
            tag: bytes32(0),
            lastUpdate: block.timestamp
        });

        // Track for lookups
        _agentValidations[agentId].push(requestHash);
        _validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestUri, requestHash);
    }

    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseUri,
        bytes32 responseHash,
        bytes32 tag
    ) external {
        ValidationStatus storage s = validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        require(msg.sender == s.validatorAddress, "not validator");
        require(response <= 100, "resp>100");
        s.response = response;
        s.responseHash = responseHash;
        s.tag = tag;
        s.lastUpdate = block.timestamp;
        emit ValidationResponse(s.validatorAddress, s.agentId, requestHash, response, responseUri, responseHash, tag);
    }

    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, bytes32 tag, uint256 lastUpdate)
    {
        ValidationStatus memory s = validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        return (s.validatorAddress, s.agentId, s.response, s.responseHash, s.tag, s.lastUpdate);
    }

    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        bytes32 tag
    ) external view returns (uint64 count, uint8 avgResponse) {
        uint256 totalResponse = 0;
        count = 0;

        bytes32[] storage requestHashes = _agentValidations[agentId];

        for (uint256 i = 0; i < requestHashes.length; i++) {
            ValidationStatus storage s = validations[requestHashes[i]];

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

            if (matchValidator && matchTag && s.response >= 0) {
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
}
