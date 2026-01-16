// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";

contract ValidationRegistryTest is TestBase {
    // ============================================================
    // Events (redeclared for expectEmit)
    // ============================================================
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

    // ============================================================
    // getIdentityRegistry()
    // ============================================================

    function test_getIdentityRegistry() public view {
        assertEq(validationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    // ============================================================
    // validationRequest() - Success cases
    // ============================================================

    function test_validationRequest_byOwner(
        address validator,
        string calldata requestURI,
        bytes32 requestHash
    ) public {
        vm.assume(validator != address(0));

        uint256 agentId = _registerAgent(alice);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(validator, agentId, requestURI, requestHash);

        vm.prank(alice);
        validationRegistry.validationRequest(validator, agentId, requestURI, requestHash);

        // Verify storage changes
        (
            address storedValidator,
            uint256 storedAgentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(requestHash);

        assertEq(storedValidator, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 0);
        assertEq(responseHash, bytes32(0));
        assertEq(tag, "");
        assertEq(lastUpdate, block.timestamp);

        // Verify tracking arrays
        bytes32[] memory agentValidations = validationRegistry.getAgentValidations(agentId);
        assertEq(agentValidations.length, 1);
        assertEq(agentValidations[0], requestHash);

        bytes32[] memory validatorRequests = validationRegistry.getValidatorRequests(validator);
        assertEq(validatorRequests.length, 1);
        assertEq(validatorRequests[0], requestHash);
    }

    function test_validationRequest_byOperator(
        address validator,
        string calldata requestURI,
        bytes32 requestHash
    ) public {
        vm.assume(validator != address(0));

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(validator, agentId, requestURI, requestHash);

        vm.prank(bob);
        validationRegistry.validationRequest(validator, agentId, requestURI, requestHash);

        // Verify all storage fields
        (
            address storedValidator,
            uint256 storedAgentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(requestHash);

        assertEq(storedValidator, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 0);
        assertEq(responseHash, bytes32(0));
        assertEq(tag, "");
        assertEq(lastUpdate, block.timestamp);

        // Verify tracking arrays
        bytes32[] memory agentValidations = validationRegistry.getAgentValidations(agentId);
        assertEq(agentValidations.length, 1);
        assertEq(agentValidations[0], requestHash);

        bytes32[] memory validatorRequests = validationRegistry.getValidatorRequests(validator);
        assertEq(validatorRequests.length, 1);
        assertEq(validatorRequests[0], requestHash);
    }

    function test_validationRequest_byApproved(
        address validator,
        string calldata requestURI,
        bytes32 requestHash
    ) public {
        vm.assume(validator != address(0));

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(charlie, agentId);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(validator, agentId, requestURI, requestHash);

        vm.prank(charlie);
        validationRegistry.validationRequest(validator, agentId, requestURI, requestHash);

        // Verify all storage fields
        (
            address storedValidator,
            uint256 storedAgentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(requestHash);

        assertEq(storedValidator, validator);
        assertEq(storedAgentId, agentId);
        assertEq(response, 0);
        assertEq(responseHash, bytes32(0));
        assertEq(tag, "");
        assertEq(lastUpdate, block.timestamp);

        // Verify tracking arrays
        bytes32[] memory agentValidations = validationRegistry.getAgentValidations(agentId);
        assertEq(agentValidations.length, 1);
        assertEq(agentValidations[0], requestHash);

        bytes32[] memory validatorRequests = validationRegistry.getValidatorRequests(validator);
        assertEq(validatorRequests.length, 1);
        assertEq(validatorRequests[0], requestHash);
    }

    function test_validationRequest_multipleRequests() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("request1");
        bytes32 hash2 = keccak256("request2");
        bytes32 hash3 = keccak256("request3");

        vm.startPrank(alice);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(bob, agentId, "uri1", hash1);
        validationRegistry.validationRequest(bob, agentId, "uri1", hash1);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(charlie, agentId, "uri2", hash2);
        validationRegistry.validationRequest(charlie, agentId, "uri2", hash2);

        vm.expectEmit(true, true, true, true);
        emit ValidationRequest(bob, agentId, "uri3", hash3);
        validationRegistry.validationRequest(bob, agentId, "uri3", hash3);

        vm.stopPrank();

        // Verify all stored correctly
        (address v1,,,,,) = validationRegistry.getValidationStatus(hash1);
        (address v2,,,,,) = validationRegistry.getValidationStatus(hash2);
        (address v3,,,,,) = validationRegistry.getValidationStatus(hash3);

        assertEq(v1, bob);
        assertEq(v2, charlie);
        assertEq(v3, bob);

        // Verify agent tracking
        bytes32[] memory agentValidations = validationRegistry.getAgentValidations(agentId);
        assertEq(agentValidations.length, 3);
        assertEq(agentValidations[0], hash1);
        assertEq(agentValidations[1], hash2);
        assertEq(agentValidations[2], hash3);

        // Verify validator tracking
        bytes32[] memory bobRequests = validationRegistry.getValidatorRequests(bob);
        assertEq(bobRequests.length, 2);
        assertEq(bobRequests[0], hash1);
        assertEq(bobRequests[1], hash3);

        bytes32[] memory charlieRequests = validationRegistry.getValidatorRequests(charlie);
        assertEq(charlieRequests.length, 1);
        assertEq(charlieRequests[0], hash2);
    }

    // ============================================================
    // validationRequest() - Revert cases
    // ============================================================

    function test_validationRequest_revertsWhenValidatorIsZero(
        string calldata requestURI,
        bytes32 requestHash
    ) public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        vm.expectRevert("bad validator");
        validationRegistry.validationRequest(address(0), agentId, requestURI, requestHash);
    }

    function test_validationRequest_revertsWhenRequestHashExists() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("duplicate");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "uri1", requestHash);

        vm.prank(alice);
        vm.expectRevert("exists");
        validationRegistry.validationRequest(charlie, agentId, "uri2", requestHash);
    }

    function test_validationRequest_revertsWhenNotAuthorized(
        address unauthorized,
        bytes32 requestHash
    ) public {
        vm.assume(unauthorized != alice);
        vm.assume(unauthorized != address(0));

        uint256 agentId = _registerAgent(alice);

        vm.prank(unauthorized);
        vm.expectRevert("Not authorized");
        validationRegistry.validationRequest(bob, agentId, "uri", requestHash);
    }

    function test_validationRequest_revertsWhenAgentDoesNotExist(uint256 agentId) public {
        vm.prank(alice);
        vm.expectRevert(); // ERC721NonexistentToken
        validationRegistry.validationRequest(bob, agentId, "uri", keccak256("test"));
    }

    // ============================================================
    // validationResponse() - Success cases
    // ============================================================

    function test_validationResponse(
        uint8 response,
        string calldata responseURI,
        bytes32 responseHash,
        string calldata tag
    ) public {
        response = uint8(bound(response, 0, 100));

        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "requestURI", requestHash);

        vm.expectEmit(true, true, true, true);
        emit ValidationResponse(bob, agentId, requestHash, response, responseURI, responseHash, tag);

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, response, responseURI, responseHash, tag);

        // Verify storage changes
        (
            address storedValidator,
            uint256 storedAgentId,
            uint8 storedResponse,
            bytes32 storedResponseHash,
            string memory storedTag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(requestHash);

        assertEq(storedValidator, bob);
        assertEq(storedAgentId, agentId);
        assertEq(storedResponse, response);
        assertEq(storedResponseHash, responseHash);
        assertEq(storedTag, tag);
        assertEq(lastUpdate, block.timestamp);
    }

    function test_validationResponse_boundaryValues() public {
        uint256 agentId = _registerAgent(alice);

        // Response 0
        bytes32 hash1 = keccak256("request1");
        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);

        vm.expectEmit(true, true, true, true);
        emit ValidationResponse(bob, agentId, hash1, 0, "uri0", keccak256("resp0"), "tag0");

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 0, "uri0", keccak256("resp0"), "tag0");

        (
            address v1,
            uint256 a1,
            uint8 response1,
            bytes32 respHash1,
            string memory tag1,
            uint256 lastUpdate1
        ) = validationRegistry.getValidationStatus(hash1);
        assertEq(v1, bob);
        assertEq(a1, agentId);
        assertEq(response1, 0);
        assertEq(respHash1, keccak256("resp0"));
        assertEq(tag1, "tag0");
        assertEq(lastUpdate1, block.timestamp);

        // Response 100
        bytes32 hash2 = keccak256("request2");
        vm.prank(alice);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);

        vm.expectEmit(true, true, true, true);
        emit ValidationResponse(charlie, agentId, hash2, 100, "uri100", keccak256("resp100"), "tag100");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash2, 100, "uri100", keccak256("resp100"), "tag100");

        (
            address v2,
            uint256 a2,
            uint8 response2,
            bytes32 respHash2,
            string memory tag2,
            uint256 lastUpdate2
        ) = validationRegistry.getValidationStatus(hash2);
        assertEq(v2, charlie);
        assertEq(a2, agentId);
        assertEq(response2, 100);
        assertEq(respHash2, keccak256("resp100"));
        assertEq(tag2, "tag100");
        assertEq(lastUpdate2, block.timestamp);
    }

    function test_validationResponse_canUpdateMultipleTimes() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        uint256 firstTimestamp = block.timestamp;

        // First response
        vm.expectEmit(true, true, true, true);
        emit ValidationResponse(bob, agentId, requestHash, 50, "uri1", keccak256("hash1"), "tag1");

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 50, "uri1", keccak256("hash1"), "tag1");

        (
            address v1,
            uint256 a1,
            uint8 response1,
            bytes32 respHash1,
            string memory tag1,
            uint256 lastUpdate1
        ) = validationRegistry.getValidationStatus(requestHash);
        assertEq(v1, bob);
        assertEq(a1, agentId);
        assertEq(response1, 50);
        assertEq(respHash1, keccak256("hash1"));
        assertEq(tag1, "tag1");
        assertEq(lastUpdate1, firstTimestamp);

        // Update response after time passes
        vm.warp(block.timestamp + 1 hours);
        uint256 secondTimestamp = block.timestamp;

        vm.expectEmit(true, true, true, true);
        emit ValidationResponse(bob, agentId, requestHash, 80, "uri2", keccak256("hash2"), "tag2");

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 80, "uri2", keccak256("hash2"), "tag2");

        (
            address v2,
            uint256 a2,
            uint8 response2,
            bytes32 respHash2,
            string memory tag2,
            uint256 lastUpdate2
        ) = validationRegistry.getValidationStatus(requestHash);
        assertEq(v2, bob);
        assertEq(a2, agentId);
        assertEq(response2, 80);
        assertEq(respHash2, keccak256("hash2"));
        assertEq(tag2, "tag2");
        assertEq(lastUpdate2, secondTimestamp);

        // Verify lastUpdate changed
        assertTrue(lastUpdate2 > lastUpdate1);
    }

    // ============================================================
    // validationResponse() - Revert cases
    // ============================================================

    function test_validationResponse_revertsWhenUnknownRequest(bytes32 requestHash) public {
        vm.prank(bob);
        vm.expectRevert("unknown");
        validationRegistry.validationResponse(requestHash, 50, "", bytes32(0), "");
    }

    function test_validationResponse_revertsWhenNotValidator() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        // Charlie tries to respond (not the validator)
        vm.prank(charlie);
        vm.expectRevert("not validator");
        validationRegistry.validationResponse(requestHash, 50, "", bytes32(0), "");
    }

    function test_validationResponse_revertsWhenResponseExceeds100(uint8 response) public {
        response = uint8(bound(response, 101, 255));

        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        vm.prank(bob);
        vm.expectRevert("resp>100");
        validationRegistry.validationResponse(requestHash, response, "", bytes32(0), "");
    }

    // ============================================================
    // getValidationStatus()
    // ============================================================

    function test_getValidationStatus() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "requestURI", requestHash);

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 85, "responseURI", keccak256("response"), "audit");

        (
            address validator,
            uint256 storedAgentId,
            uint8 response,
            bytes32 responseHash,
            string memory tag,
            uint256 lastUpdate
        ) = validationRegistry.getValidationStatus(requestHash);

        assertEq(validator, bob);
        assertEq(storedAgentId, agentId);
        assertEq(response, 85);
        assertEq(responseHash, keccak256("response"));
        assertEq(tag, "audit");
        assertEq(lastUpdate, block.timestamp);
    }

    function test_getValidationStatus_revertsWhenUnknown(bytes32 requestHash) public {
        vm.expectRevert("unknown");
        validationRegistry.getValidationStatus(requestHash);
    }

    // ============================================================
    // getSummary()
    // ============================================================

    function test_getSummary_noFilters() public {
        uint256 agentId = _registerAgent(alice);

        // Create 3 validation requests with responses
        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");
        bytes32 hash3 = keccak256("req3");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        validationRegistry.validationRequest(malicious, agentId, "", hash3);
        vm.stopPrank();

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash2, 90, "", bytes32(0), "");

        vm.prank(malicious);
        validationRegistry.validationResponse(hash3, 70, "", bytes32(0), "");

        address[] memory noValidators = new address[](0);
        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, noValidators, "");

        assertEq(count, 3);
        assertEq(avgResponse, 80); // (80 + 90 + 70) / 3 = 80
    }

    function test_getSummary_filterByValidators() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");
        bytes32 hash3 = keccak256("req3");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        validationRegistry.validationRequest(malicious, agentId, "", hash3);
        vm.stopPrank();

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash2, 90, "", bytes32(0), "");

        vm.prank(malicious);
        validationRegistry.validationResponse(hash3, 70, "", bytes32(0), "");

        // Filter to only bob and charlie
        address[] memory validators = new address[](2);
        validators[0] = bob;
        validators[1] = charlie;

        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, validators, "");

        assertEq(count, 2);
        assertEq(avgResponse, 85); // (80 + 90) / 2 = 85
    }

    function test_getSummary_filterByTag() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");
        bytes32 hash3 = keccak256("req3");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        validationRegistry.validationRequest(malicious, agentId, "", hash3);
        vm.stopPrank();

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "audit");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash2, 90, "", bytes32(0), "audit");

        vm.prank(malicious);
        validationRegistry.validationResponse(hash3, 70, "", bytes32(0), "review");

        address[] memory noValidators = new address[](0);
        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, noValidators, "audit");

        assertEq(count, 2);
        assertEq(avgResponse, 85); // (80 + 90) / 2 = 85
    }

    function test_getSummary_filterByValidatorsAndTag() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");
        bytes32 hash3 = keccak256("req3");
        bytes32 hash4 = keccak256("req4");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(bob, agentId, "", hash2);
        validationRegistry.validationRequest(charlie, agentId, "", hash3);
        validationRegistry.validationRequest(charlie, agentId, "", hash4);
        vm.stopPrank();

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "audit");

        vm.prank(bob);
        validationRegistry.validationResponse(hash2, 60, "", bytes32(0), "review");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash3, 90, "", bytes32(0), "audit");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash4, 70, "", bytes32(0), "review");

        // Filter to bob with "audit" tag
        address[] memory validators = new address[](1);
        validators[0] = bob;

        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, validators, "audit");

        assertEq(count, 1);
        assertEq(avgResponse, 80);
    }

    function test_getSummary_excludesRequestsWithoutResponse() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        vm.stopPrank();

        // Only bob responds
        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "");

        address[] memory noValidators = new address[](0);
        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, noValidators, "");

        assertEq(count, 1);
        assertEq(avgResponse, 80);
    }

    function test_getSummary_noResponses() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);

        // No response given
        address[] memory noValidators = new address[](0);
        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, noValidators, "");

        assertEq(count, 0);
        assertEq(avgResponse, 0);
    }

    function test_getSummary_noValidations() public {
        uint256 agentId = _registerAgent(alice);

        address[] memory noValidators = new address[](0);
        (uint64 count, uint8 avgResponse) = validationRegistry.getSummary(agentId, noValidators, "");

        assertEq(count, 0);
        assertEq(avgResponse, 0);
    }

    // ============================================================
    // getAgentValidations()
    // ============================================================

    function test_getAgentValidations() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        vm.stopPrank();

        bytes32[] memory validations = validationRegistry.getAgentValidations(agentId);

        assertEq(validations.length, 2);
        assertEq(validations[0], hash1);
        assertEq(validations[1], hash2);
    }

    function test_getAgentValidations_emptyForNewAgent() public {
        uint256 agentId = _registerAgent(alice);

        bytes32[] memory validations = validationRegistry.getAgentValidations(agentId);
        assertEq(validations.length, 0);
    }

    // ============================================================
    // getValidatorRequests()
    // ============================================================

    function test_getValidatorRequests() public {
        uint256 agentId1 = _registerAgent(alice);
        uint256 agentId2 = _registerAgent(bob);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");

        vm.prank(alice);
        validationRegistry.validationRequest(charlie, agentId1, "", hash1);

        vm.prank(bob);
        validationRegistry.validationRequest(charlie, agentId2, "", hash2);

        bytes32[] memory requests = validationRegistry.getValidatorRequests(charlie);

        assertEq(requests.length, 2);
        assertEq(requests[0], hash1);
        assertEq(requests[1], hash2);
    }

    function test_getValidatorRequests_emptyForNewValidator() public {
        bytes32[] memory requests = validationRegistry.getValidatorRequests(bob);
        assertEq(requests.length, 0);
    }

    // ============================================================
    // Gas Profiling Tests
    // ============================================================

    function test_validationRequest_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "ipfs://request", keccak256("request"));
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "validationRequest");
    }

    function test_validationResponse_gas() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 85, "ipfs://response", keccak256("response"), "audit");
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "validationResponse");
    }

    function test_validationResponse_update_gas() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 50, "", bytes32(0), "");

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 85, "ipfs://updated", keccak256("updated"), "audit");
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "validationResponse (update)");
    }

    function test_getValidationStatus_gas() public {
        uint256 agentId = _registerAgent(alice);
        bytes32 requestHash = keccak256("request");

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", requestHash);

        vm.prank(bob);
        validationRegistry.validationResponse(requestHash, 85, "", bytes32(0), "audit");

        validationRegistry.getValidationStatus(requestHash);
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "getValidationStatus");
    }

    function test_getSummary_gas() public {
        uint256 agentId = _registerAgent(alice);

        bytes32 hash1 = keccak256("req1");
        bytes32 hash2 = keccak256("req2");

        vm.startPrank(alice);
        validationRegistry.validationRequest(bob, agentId, "", hash1);
        validationRegistry.validationRequest(charlie, agentId, "", hash2);
        vm.stopPrank();

        vm.prank(bob);
        validationRegistry.validationResponse(hash1, 80, "", bytes32(0), "");

        vm.prank(charlie);
        validationRegistry.validationResponse(hash2, 90, "", bytes32(0), "");

        address[] memory noValidators = new address[](0);
        validationRegistry.getSummary(agentId, noValidators, "");
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "getSummary");
    }

    function test_getAgentValidations_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", keccak256("req1"));

        validationRegistry.getAgentValidations(agentId);
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "getAgentValidations");
    }

    function test_getValidatorRequests_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        validationRegistry.validationRequest(bob, agentId, "", keccak256("req1"));

        validationRegistry.getValidatorRequests(bob);
        vm.snapshotGasLastCall("ValidationRegistryUpgradeable", "getValidatorRequests");
    }
}
