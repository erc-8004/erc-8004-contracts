// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IIdentityRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract ValidationRegistryUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    event ValidationRequest(
        address indexed validatorAddress,
        uint256 indexed agentId,
        string requestURI,
        bytes32 indexed requestHash
    );

    event ValidationResponse(
        address indexed validatorAddress,
        uint256 indexed agentId,
        bytes32 indexed requestHash,
        uint8 response,
        string responseURI,
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

    /// @dev Identity registry address stored at slot 0 (matches MinimalUUPS)
    address private _identityRegistry;

    /// @custom:storage-location erc7201:erc8004.validation.registry
    struct ValidationRegistryStorage {
        // requestHash => validation status
        mapping(bytes32 => ValidationStatus) validations;
        // agentId => list of requestHashes
        mapping(uint256 => bytes32[]) _agentValidations;
        // validatorAddress => list of requestHashes
        mapping(address => bytes32[]) _validatorRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("erc8004.validation.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VALIDATION_REGISTRY_STORAGE_LOCATION =
        0x21543a2dd0df813994fbf82c69c61d1aafcdce183d68d2ef40068bdce1481100;

    function _getValidationRegistryStorage() private pure returns (ValidationRegistryStorage storage $) {
        assembly {
            $.slot := VALIDATION_REGISTRY_STORAGE_LOCATION
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

    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestURI,
        bytes32 requestHash
    ) external {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        require(validatorAddress != address(0), "bad validator");
        require($.validations[requestHash].validatorAddress == address(0), "exists");

        // Check permission: caller must be owner or approved operator
        IIdentityRegistry registry = IIdentityRegistry(_identityRegistry);
        address owner = registry.ownerOf(agentId);
        require(
            msg.sender == owner ||
            registry.isApprovedForAll(owner, msg.sender) ||
            registry.getApproved(agentId) == msg.sender,
            "Not authorized"
        );

        $.validations[requestHash] = ValidationStatus({
            validatorAddress: validatorAddress,
            agentId: agentId,
            response: 0,
            responseHash: bytes32(0),
            tag: "",
            lastUpdate: block.timestamp,
            hasResponse: false
        });

        // Track for lookups
        $._agentValidations[agentId].push(requestHash);
        $._validatorRequests[validatorAddress].push(requestHash);

        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }

    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) external {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        ValidationStatus storage s = $.validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        require(msg.sender == s.validatorAddress, "not validator");
        require(response <= 100, "resp>100");
        s.response = response;
        s.responseHash = responseHash;
        s.tag = tag;
        s.lastUpdate = block.timestamp;
        s.hasResponse = true;
        emit ValidationResponse(s.validatorAddress, s.agentId, requestHash, response, responseURI, responseHash, tag);
    }

    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, string memory tag, uint256 lastUpdate)
    {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        ValidationStatus memory s = $.validations[requestHash];
        require(s.validatorAddress != address(0), "unknown");
        return (s.validatorAddress, s.agentId, s.response, s.responseHash, s.tag, s.lastUpdate);
    }

    function getSummary(
        uint256 agentId,
        address[] calldata validatorAddresses,
        string calldata tag
    ) external view returns (uint64 count, uint8 avgResponse) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        uint256 totalResponse;

        bytes32[] storage requestHashes = $._agentValidations[agentId];

        for (uint256 i; i < requestHashes.length; i++) {
            ValidationStatus storage s = $.validations[requestHashes[i]];

            // Filter by validator if specified
            bool matchValidator = (validatorAddresses.length == 0);
            if (!matchValidator) {
                for (uint256 j; j < validatorAddresses.length; j++) {
                    if (s.validatorAddress == validatorAddresses[j]) {
                        matchValidator = true;
                        break;
                    }
                }
            }

            // Filter by tag (empty string means no filter)
            bool matchTag = (bytes(tag).length == 0) || (keccak256(bytes(s.tag)) == keccak256(bytes(tag)));

            if (matchValidator && matchTag && s.hasResponse) {
                totalResponse += s.response;
                count++;
            }
        }

        avgResponse = count > 0 ? uint8(totalResponse / count) : 0;
    }

    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        return $._agentValidations[agentId];
    }

    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory) {
        ValidationRegistryStorage storage $ = _getValidationRegistryStorage();
        return $._validatorRequests[validatorAddress];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "2.0.0";
    }
}
