// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract ValidationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    address private identityRegistry;

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
        string tag
    );

    struct ValidationStatus {
        address validatorAddress;
        uint256 agentId;
        uint8 response;       // 0..100
        bytes32 responseHash;
        string tag;
        uint256 lastUpdate;
        bool hasResponse;
    }

    // requestHash => validation status
    mapping(bytes32 => ValidationStatus) public validations;

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
            msg.sender == owner || registry.isApprovedForAll(owner, msg.sender),
            "Not authorized"
        );

        validations[requestHash] = ValidationStatus({
            validatorAddress: validatorAddress,
            agentId: agentId,
            response: 0,
            responseHash: bytes32(0),
            tag: "",
            lastUpdate: block.timestamp,
            hasResponse: false
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
        string calldata tag
    ) external {
        ValidationStatus storage s = validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        require(msg.sender == s.validatorAddress, "not validator");
        require(response <= 100, "resp>100");
        s.response = response;
        s.responseHash = responseHash;
        s.tag = tag;
        s.lastUpdate = block.timestamp;
        s.hasResponse = true;
        emit ValidationResponse(s.validatorAddress, s.agentId, requestHash, response, responseUri, responseHash, tag);
    }

    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, string memory tag, uint256 lastUpdate)
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
            bool matchTag = (keccak256(abi.encodePacked(tag)) == keccak256(abi.encodePacked(""))) || (keccak256(abi.encodePacked(s.tag)) == keccak256(abi.encodePacked(tag)));

            if (matchValidator && matchTag && s.hasResponse) {
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
