// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {ReputationRegistryUpgradeable} from "../contracts/ReputationRegistryUpgradeable.sol";

contract ReputationRegistryTest is TestBase {
    // ============================================================
    // Events (redeclared for expectEmit)
    // ============================================================
    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        uint8 score,
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

    // ============================================================
    // Setup helpers
    // ============================================================

    function _createAgentAndClient() internal returns (uint256 agentId, address client) {
        agentId = _registerAgent(alice);
        client = bob;
    }

    // ============================================================
    // getIdentityRegistry()
    // ============================================================

    function test_getIdentityRegistry() public view {
        assertEq(reputationRegistry.getIdentityRegistry(), address(identityRegistry));
    }

    // ============================================================
    // giveFeedback() - Success cases
    // ============================================================

    function test_giveFeedback(
        uint8 score,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) public {
        score = uint8(bound(score, 0, 100));

        uint256 agentId = _registerAgent(alice);

        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, bob, 1, score, tag1, tag1, tag2, endpoint, feedbackURI, feedbackHash);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, score, tag1, tag2, endpoint, feedbackURI, feedbackHash);

        // Verify storage changes
        assertEq(reputationRegistry.getLastIndex(agentId, bob), 1);
        
        (uint8 storedScore, string memory storedTag1, string memory storedTag2, bool isRevoked) = 
            reputationRegistry.readFeedback(agentId, bob, 1);
        assertEq(storedScore, score);
        assertEq(storedTag1, tag1);
        assertEq(storedTag2, tag2);
        assertFalse(isRevoked);

        // Verify client tracking
        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
    }

    function test_giveFeedback_multipleFeedbackFromSameClient() public {
        uint256 agentId = _registerAgent(alice);

        // First feedback
        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, bob, 1, 80, "tag1", "tag1", "tag2", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "", "", bytes32(0));

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 1);

        // Second feedback
        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, bob, 2, 90, "tag3", "tag3", "tag4", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 90, "tag3", "tag4", "", "", bytes32(0));

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 2);

        // Third feedback
        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, bob, 3, 70, "tag5", "tag5", "tag6", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 70, "tag5", "tag6", "", "", bytes32(0));

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 3);

        // Verify all feedback stored correctly (score and tags)
        (uint8 score1, string memory t1_1, string memory t2_1, bool rev1) = reputationRegistry.readFeedback(agentId, bob, 1);
        (uint8 score2, string memory t1_2, string memory t2_2, bool rev2) = reputationRegistry.readFeedback(agentId, bob, 2);
        (uint8 score3, string memory t1_3, string memory t2_3, bool rev3) = reputationRegistry.readFeedback(agentId, bob, 3);

        assertEq(score1, 80);
        assertEq(t1_1, "tag1");
        assertEq(t2_1, "tag2");
        assertFalse(rev1);

        assertEq(score2, 90);
        assertEq(t1_2, "tag3");
        assertEq(t2_2, "tag4");
        assertFalse(rev2);

        assertEq(score3, 70);
        assertEq(t1_3, "tag5");
        assertEq(t2_3, "tag6");
        assertFalse(rev3);

        // Client should only be tracked once
        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
    }

    function test_giveFeedback_multipleClients() public {
        uint256 agentId = _registerAgent(alice);

        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, bob, 1, 80, "b1", "b1", "b2", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "b1", "b2", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, charlie, 1, 90, "c1", "c1", "c2", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "c1", "c2", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit NewFeedback(agentId, malicious, 1, 70, "m1", "m1", "m2", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "m1", "m2", "", "", bytes32(0));

        // Verify each client has their own index
        assertEq(reputationRegistry.getLastIndex(agentId, bob), 1);
        assertEq(reputationRegistry.getLastIndex(agentId, charlie), 1);
        assertEq(reputationRegistry.getLastIndex(agentId, malicious), 1);

        // Verify feedback data for each client
        (uint8 scoreB, string memory t1B, string memory t2B, bool revB) = reputationRegistry.readFeedback(agentId, bob, 1);
        assertEq(scoreB, 80);
        assertEq(t1B, "b1");
        assertEq(t2B, "b2");
        assertFalse(revB);

        (uint8 scoreC, string memory t1C, string memory t2C, bool revC) = reputationRegistry.readFeedback(agentId, charlie, 1);
        assertEq(scoreC, 90);
        assertEq(t1C, "c1");
        assertEq(t2C, "c2");
        assertFalse(revC);

        (uint8 scoreM, string memory t1M, string memory t2M, bool revM) = reputationRegistry.readFeedback(agentId, malicious, 1);
        assertEq(scoreM, 70);
        assertEq(t1M, "m1");
        assertEq(t2M, "m2");
        assertFalse(revM);

        // Verify all clients tracked
        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 3);
        assertEq(clients[0], bob);
        assertEq(clients[1], charlie);
        assertEq(clients[2], malicious);
    }

    function test_giveFeedback_boundaryScores() public {
        uint256 agentId = _registerAgent(alice);

        // Score 0
        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 0, "", "", "", "", bytes32(0));

        (uint8 score0,,,) = reputationRegistry.readFeedback(agentId, bob, 1);
        assertEq(score0, 0);

        // Score 100
        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 100, "", "", "", "", bytes32(0));

        (uint8 score100,,,) = reputationRegistry.readFeedback(agentId, charlie, 1);
        assertEq(score100, 100);
    }

    // ============================================================
    // giveFeedback() - Revert cases
    // ============================================================

    function test_giveFeedback_revertsWhenScoreExceeds100(uint8 score) public {
        score = uint8(bound(score, 101, 255));

        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        vm.expectRevert("score>100");
        reputationRegistry.giveFeedback(agentId, score, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsWhenAgentDoesNotExist(uint256 agentId) public {
        vm.prank(bob);
        vm.expectRevert("Agent does not exist");
        reputationRegistry.giveFeedback(agentId, 50, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsWhenCallerIsOwner() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        vm.expectRevert("Self-feedback not allowed");
        reputationRegistry.giveFeedback(agentId, 50, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsWhenCallerIsOperator() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        vm.prank(bob);
        vm.expectRevert("Self-feedback not allowed");
        reputationRegistry.giveFeedback(agentId, 50, "", "", "", "", bytes32(0));
    }

    function test_giveFeedback_revertsWhenCallerIsApproved() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(bob, agentId);

        vm.prank(bob);
        vm.expectRevert("Self-feedback not allowed");
        reputationRegistry.giveFeedback(agentId, 50, "", "", "", "", bytes32(0));
    }

    // ============================================================
    // revokeFeedback()
    // ============================================================

    function test_revokeFeedback() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit FeedbackRevoked(agentId, bob, 1);

        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);

        // Verify storage changes - isRevoked should be true, but score/tags preserved
        (uint8 score, string memory tag1, string memory tag2, bool isRevoked) = 
            reputationRegistry.readFeedback(agentId, bob, 1);
        assertTrue(isRevoked);
        assertEq(score, 80);
        assertEq(tag1, "tag1");
        assertEq(tag2, "tag2");

        // Verify lastIndex unchanged
        assertEq(reputationRegistry.getLastIndex(agentId, bob), 1);

        // Verify client still tracked
        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
    }

    function test_revokeFeedback_specificIndex() public {
        uint256 agentId = _registerAgent(alice);

        // Create multiple feedback
        vm.startPrank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "t1", "t2", "", "", bytes32(0));
        reputationRegistry.giveFeedback(agentId, 90, "t3", "t4", "", "", bytes32(0));
        reputationRegistry.giveFeedback(agentId, 70, "t5", "t6", "", "", bytes32(0));
        vm.stopPrank();

        // Revoke only the second one
        vm.expectEmit(true, true, true, true);
        emit FeedbackRevoked(agentId, bob, 2);

        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 2);

        // Verify only index 2 is revoked, others unchanged
        (uint8 score1, string memory t1_1, string memory t2_1, bool revoked1) = reputationRegistry.readFeedback(agentId, bob, 1);
        (uint8 score2, string memory t1_2, string memory t2_2, bool revoked2) = reputationRegistry.readFeedback(agentId, bob, 2);
        (uint8 score3, string memory t1_3, string memory t2_3, bool revoked3) = reputationRegistry.readFeedback(agentId, bob, 3);

        assertFalse(revoked1);
        assertEq(score1, 80);
        assertEq(t1_1, "t1");
        assertEq(t2_1, "t2");

        assertTrue(revoked2);
        assertEq(score2, 90);
        assertEq(t1_2, "t3");
        assertEq(t2_2, "t4");

        assertFalse(revoked3);
        assertEq(score3, 70);
        assertEq(t1_3, "t5");
        assertEq(t2_3, "t6");

        // lastIndex should still be 3
        assertEq(reputationRegistry.getLastIndex(agentId, bob), 3);
    }

    function test_revokeFeedback_revertsWhenIndexZero() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(bob);
        vm.expectRevert("index must be > 0");
        reputationRegistry.revokeFeedback(agentId, 0);
    }

    function test_revokeFeedback_revertsWhenIndexOutOfBounds(uint64 feedbackIndex) public {
        feedbackIndex = uint64(bound(feedbackIndex, 2, type(uint64).max));

        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(bob);
        vm.expectRevert("index out of bounds");
        reputationRegistry.revokeFeedback(agentId, feedbackIndex);
    }

    function test_revokeFeedback_revertsWhenAlreadyRevoked() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);

        vm.prank(bob);
        vm.expectRevert("Already revoked");
        reputationRegistry.revokeFeedback(agentId, 1);
    }

    function test_revokeFeedback_revertsWhenNotOriginalClient() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        // Charlie tries to revoke Bob's feedback
        vm.prank(charlie);
        vm.expectRevert("index out of bounds");
        reputationRegistry.revokeFeedback(agentId, 1);
    }

    // ============================================================
    // appendResponse()
    // ============================================================

    function test_appendResponse(
        string calldata responseURI,
        bytes32 responseHash
    ) public {
        vm.assume(bytes(responseURI).length > 0);

        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, charlie, responseURI, responseHash);

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, responseURI, responseHash);

        // Verify storage changes
        address[] memory noFilter = new address[](0);
        uint64 count = reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        assertEq(count, 1);
    }

    function test_appendResponse_byAgentOwner() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        // Agent owner can respond (e.g., to show refund)
        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, alice, "ipfs://refund", bytes32(0));

        vm.prank(alice);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://refund", bytes32(0));

        address[] memory noFilter = new address[](0);
        uint64 count = reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        assertEq(count, 1);

        // Verify per-responder count
        address[] memory aliceFilter = new address[](1);
        aliceFilter[0] = alice;
        assertEq(reputationRegistry.getResponseCount(agentId, bob, 1, aliceFilter), 1);
    }

    function test_appendResponse_multipleResponses() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        // Multiple responses from same responder - verify each event
        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, charlie, "ipfs://response1", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response1", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, charlie, "ipfs://response2", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response2", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, charlie, "ipfs://response3", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response3", bytes32(0));

        // Verify total count
        address[] memory noFilter = new address[](0);
        uint64 totalCount = reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        assertEq(totalCount, 3);

        // Verify per-responder count
        address[] memory charlieFilter = new address[](1);
        charlieFilter[0] = charlie;
        uint64 charlieCount = reputationRegistry.getResponseCount(agentId, bob, 1, charlieFilter);
        assertEq(charlieCount, 3);
    }

    function test_appendResponse_multipleResponders() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, alice, "ipfs://alice", bytes32(0));

        vm.prank(alice);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://alice", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, charlie, "ipfs://charlie", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://charlie", bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ResponseAppended(agentId, bob, 1, malicious, "ipfs://malicious", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://malicious", bytes32(0));

        // Verify total count
        address[] memory noFilter = new address[](0);
        uint64 totalCount = reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        assertEq(totalCount, 3);

        // Verify per-responder counts
        address[] memory aliceFilter = new address[](1);
        aliceFilter[0] = alice;
        assertEq(reputationRegistry.getResponseCount(agentId, bob, 1, aliceFilter), 1);

        address[] memory charlieFilter = new address[](1);
        charlieFilter[0] = charlie;
        assertEq(reputationRegistry.getResponseCount(agentId, bob, 1, charlieFilter), 1);

        address[] memory maliciousFilter = new address[](1);
        maliciousFilter[0] = malicious;
        assertEq(reputationRegistry.getResponseCount(agentId, bob, 1, maliciousFilter), 1);
    }

    function test_appendResponse_revertsWhenIndexZero() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        vm.expectRevert("index must be > 0");
        reputationRegistry.appendResponse(agentId, bob, 0, "ipfs://response", bytes32(0));
    }

    function test_appendResponse_revertsWhenIndexOutOfBounds(uint64 feedbackIndex) public {
        feedbackIndex = uint64(bound(feedbackIndex, 2, type(uint64).max));

        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        vm.expectRevert("index out of bounds");
        reputationRegistry.appendResponse(agentId, bob, feedbackIndex, "ipfs://response", bytes32(0));
    }

    function test_appendResponse_revertsWhenEmptyURI() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        vm.expectRevert("Empty URI");
        reputationRegistry.appendResponse(agentId, bob, 1, "", bytes32(0));
    }

    // ============================================================
    // readFeedback()
    // ============================================================

    function test_readFeedback() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 85, "performance", "speed", "", "", bytes32(0));

        (uint8 score, string memory tag1, string memory tag2, bool isRevoked) = 
            reputationRegistry.readFeedback(agentId, bob, 1);

        assertEq(score, 85);
        assertEq(tag1, "performance");
        assertEq(tag2, "speed");
        assertFalse(isRevoked);
    }

    function test_readFeedback_revertsWhenIndexZero() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.expectRevert("index must be > 0");
        reputationRegistry.readFeedback(agentId, bob, 0);
    }

    function test_readFeedback_revertsWhenIndexOutOfBounds() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.expectRevert("index out of bounds");
        reputationRegistry.readFeedback(agentId, bob, 2);
    }

    // ============================================================
    // getSummary()
    // ============================================================

    function test_getSummary_noFilters() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "", "", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, noClients, "", "");

        assertEq(count, 3);
        assertEq(avgScore, 80); // (80 + 90 + 70) / 3 = 80
    }

    function test_getSummary_filterByClients() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "", "", "", "", bytes32(0));

        // Only count bob and charlie
        address[] memory filteredClients = new address[](2);
        filteredClients[0] = bob;
        filteredClients[1] = charlie;

        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, filteredClients, "", "");

        assertEq(count, 2);
        assertEq(avgScore, 85); // (80 + 90) / 2 = 85
    }

    function test_getSummary_filterByTag1() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "good", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "good", "", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "bad", "", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, noClients, "good", "");

        assertEq(count, 2);
        assertEq(avgScore, 85); // (80 + 90) / 2 = 85
    }

    function test_getSummary_filterByTag2() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "fast", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "fast", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "", "slow", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, noClients, "", "fast");

        assertEq(count, 2);
        assertEq(avgScore, 85);
    }

    function test_getSummary_excludesRevoked() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        // Revoke bob's feedback
        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);

        address[] memory noClients = new address[](0);
        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, noClients, "", "");

        assertEq(count, 1);
        assertEq(avgScore, 90);
    }

    function test_getSummary_noFeedback() public {
        uint256 agentId = _registerAgent(alice);

        address[] memory noClients = new address[](0);
        (uint64 count, uint8 avgScore) = reputationRegistry.getSummary(agentId, noClients, "", "");

        assertEq(count, 0);
        assertEq(avgScore, 0);
    }

    // ============================================================
    // readAllFeedback()
    // ============================================================

    function test_readAllFeedback_noFilters() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "tag3", "tag4", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (
            address[] memory clients,
            uint64[] memory indexes,
            uint8[] memory scores,
            string[] memory tag1s,
            string[] memory tag2s,
            bool[] memory revokedStatuses
        ) = reputationRegistry.readAllFeedback(agentId, noClients, "", "", false);

        assertEq(clients.length, 2);
        assertEq(scores[0], 80);
        assertEq(scores[1], 90);
        assertEq(indexes[0], 1);
        assertEq(indexes[1], 1);
        assertEq(tag1s[0], "tag1");
        assertEq(tag1s[1], "tag3");
        assertFalse(revokedStatuses[0]);
        assertFalse(revokedStatuses[1]);
    }

    function test_readAllFeedback_excludesRevokedByDefault() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        // Revoke bob's feedback
        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);

        address[] memory noClients = new address[](0);
        (
            address[] memory clients,
            ,
            uint8[] memory scores,
            ,
            ,
            
        ) = reputationRegistry.readAllFeedback(agentId, noClients, "", "", false);

        assertEq(clients.length, 1);
        assertEq(clients[0], charlie);
        assertEq(scores[0], 90);
    }

    function test_readAllFeedback_includesRevokedWhenRequested() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        // Revoke bob's feedback
        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);

        address[] memory noClients = new address[](0);
        (
            address[] memory clients,
            ,
            ,
            ,
            ,
            bool[] memory revokedStatuses
        ) = reputationRegistry.readAllFeedback(agentId, noClients, "", "", true);

        assertEq(clients.length, 2);
        assertTrue(revokedStatuses[0]); // bob's is revoked
        assertFalse(revokedStatuses[1]); // charlie's is not
    }

    function test_readAllFeedback_filterByTag1() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "good", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "bad", "", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (
            address[] memory clients,
            ,
            uint8[] memory scores,
            ,
            ,
            
        ) = reputationRegistry.readAllFeedback(agentId, noClients, "good", "", false);

        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
        assertEq(scores[0], 80);
    }

    function test_readAllFeedback_filterByTag2() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "fast", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "slow", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        (
            address[] memory clients,
            ,
            uint8[] memory scores,
            ,
            string[] memory tag2s,
            
        ) = reputationRegistry.readAllFeedback(agentId, noClients, "", "fast", false);

        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
        assertEq(scores[0], 80);
        assertEq(tag2s[0], "fast");
    }

    function test_readAllFeedback_filterByClients() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "tag3", "tag4", "", "", bytes32(0));

        vm.prank(malicious);
        reputationRegistry.giveFeedback(agentId, 70, "tag5", "tag6", "", "", bytes32(0));

        // Only get feedback from bob and charlie
        address[] memory filteredClients = new address[](2);
        filteredClients[0] = bob;
        filteredClients[1] = charlie;

        (
            address[] memory clients,
            ,
            uint8[] memory scores,
            ,
            ,
            
        ) = reputationRegistry.readAllFeedback(agentId, filteredClients, "", "", false);

        assertEq(clients.length, 2);
        assertEq(scores[0], 80);
        assertEq(scores[1], 90);
    }

    function test_readAllFeedback_filterByClientsAndTag2() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "fast", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 85, "", "slow", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "fast", "", "", bytes32(0));

        // Filter by specific client AND tag2
        address[] memory filteredClients = new address[](1);
        filteredClients[0] = bob;

        (
            address[] memory clients,
            uint64[] memory indexes,
            uint8[] memory scores,
            ,
            string[] memory tag2s,
            
        ) = reputationRegistry.readAllFeedback(agentId, filteredClients, "", "fast", false);

        assertEq(clients.length, 1);
        assertEq(clients[0], bob);
        assertEq(indexes[0], 1);
        assertEq(scores[0], 80);
        assertEq(tag2s[0], "fast");
    }

    // ============================================================
    // getResponseCount()
    // ============================================================

    function test_getResponseCount_specificFeedback() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://1", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://2", bytes32(0));

        address[] memory noFilter = new address[](0);
        uint64 count = reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        assertEq(count, 2);
    }

    function test_getResponseCount_filterByResponders() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://charlie", bytes32(0));

        vm.prank(alice);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://alice", bytes32(0));

        // Only count charlie's responses
        address[] memory responderFilter = new address[](1);
        responderFilter[0] = charlie;

        uint64 count = reputationRegistry.getResponseCount(agentId, bob, 1, responderFilter);
        assertEq(count, 1);
    }

    function test_getResponseCount_allFeedbackForClient() public {
        uint256 agentId = _registerAgent(alice);

        // Bob gives 2 feedback
        vm.startPrank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));
        vm.stopPrank();

        // Responses to both
        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://1", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 2, "ipfs://2", bytes32(0));

        // Count all responses for bob (feedbackIndex = 0)
        address[] memory noFilter = new address[](0);
        uint64 count = reputationRegistry.getResponseCount(agentId, bob, 0, noFilter);
        assertEq(count, 2);
    }

    function test_getResponseCount_allFeedbackForAgent() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        // Responses to both clients' feedback
        vm.prank(alice);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://bob", bytes32(0));

        vm.prank(alice);
        reputationRegistry.appendResponse(agentId, charlie, 1, "ipfs://charlie", bytes32(0));

        // Count all responses (clientAddress = 0)
        address[] memory noFilter = new address[](0);
        uint64 count = reputationRegistry.getResponseCount(agentId, address(0), 0, noFilter);
        assertEq(count, 2);
    }

    // ============================================================
    // getClients()
    // ============================================================

    function test_getClients() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        address[] memory clients = reputationRegistry.getClients(agentId);

        assertEq(clients.length, 2);
        assertEq(clients[0], bob);
        assertEq(clients[1], charlie);
    }

    function test_getClients_emptyForNewAgent() public {
        uint256 agentId = _registerAgent(alice);

        address[] memory clients = reputationRegistry.getClients(agentId);
        assertEq(clients.length, 0);
    }

    // ============================================================
    // getLastIndex()
    // ============================================================

    function test_getLastIndex() public {
        uint256 agentId = _registerAgent(alice);

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 0);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 1);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        assertEq(reputationRegistry.getLastIndex(agentId, bob), 2);
    }

    // ============================================================
    // Gas Profiling Tests
    // ============================================================

    function test_giveFeedback_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "https://endpoint", "ipfs://feedback", bytes32(uint256(1)));
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "giveFeedback");
    }

    function test_giveFeedback_secondFeedback_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "giveFeedback (second)");
    }

    function test_revokeFeedback_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(bob);
        reputationRegistry.revokeFeedback(agentId, 1);
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "revokeFeedback");
    }

    function test_appendResponse_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response", bytes32(uint256(1)));
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "appendResponse");
    }

    function test_appendResponse_secondResponse_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response1", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response2", bytes32(0));
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "appendResponse (second)");
    }

    function test_readFeedback_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "tag1", "tag2", "", "", bytes32(0));

        reputationRegistry.readFeedback(agentId, bob, 1);
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "readFeedback");
    }

    function test_getSummary_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.giveFeedback(agentId, 90, "", "", "", "", bytes32(0));

        address[] memory noClients = new address[](0);
        reputationRegistry.getSummary(agentId, noClients, "", "");
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "getSummary");
    }

    function test_getClients_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        reputationRegistry.getClients(agentId);
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "getClients");
    }

    function test_getLastIndex_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        reputationRegistry.getLastIndex(agentId, bob);
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "getLastIndex");
    }

    function test_getResponseCount_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(bob);
        reputationRegistry.giveFeedback(agentId, 80, "", "", "", "", bytes32(0));

        vm.prank(charlie);
        reputationRegistry.appendResponse(agentId, bob, 1, "ipfs://response", bytes32(0));

        address[] memory noFilter = new address[](0);
        reputationRegistry.getResponseCount(agentId, bob, 1, noFilter);
        vm.snapshotGasLastCall("ReputationRegistryUpgradeable", "getResponseCount");
    }
}
