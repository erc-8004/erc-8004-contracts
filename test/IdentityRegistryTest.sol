// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestBase} from "./TestBase.sol";
import {IdentityRegistryUpgradeable} from "../contracts/IdentityRegistryUpgradeable.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @dev Mock ERC1271 wallet for smart contract wallet signature verification
contract MockERC1271Wallet is IERC1271 {
    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes32 public expectedHash;
    bool public shouldSucceed = true;

    function setExpectedHash(bytes32 _hash) external {
        expectedHash = _hash;
    }

    function setShouldSucceed(bool _shouldSucceed) external {
        shouldSucceed = _shouldSucceed;
    }

    function isValidSignature(bytes32 hash, bytes memory) external view override returns (bytes4) {
        if (shouldSucceed && hash == expectedHash) {
            return ERC1271_MAGICVALUE;
        }
        return bytes4(0xffffffff);
    }
}

/// @dev Mock ERC721 receiver for safeMint testing
contract MockERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }
}

/// @dev Contract without onERC721Received - will cause revert
contract NonReceiver {}

contract IdentityRegistryTest is TestBase {
    // ============================================================
    // Events (redeclared for expectEmit)
    // ============================================================
    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ============================================================
    // Constants
    // ============================================================
    bytes32 private constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    
    uint256 private constant MAX_DEADLINE_DELAY = 5 minutes;

    // ============================================================
    // register()
    // ============================================================

    function test_register(address caller, uint8 count) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);
        count = uint8(bound(count, 1, 20));

        for (uint256 i; i < count; i++) {
            vm.expectEmit(true, true, false, true);
            emit Registered(i, "", caller);

            vm.expectEmit(true, true, true, true);
            emit Transfer(address(0), caller, i);

            vm.prank(caller);
            uint256 agentId = identityRegistry.register();

            assertEq(agentId, i, "AgentId should be sequential");
            assertEq(identityRegistry.ownerOf(agentId), caller, "Owner mismatch");
            assertEq(identityRegistry.getAgentWallet(agentId), caller, "AgentWallet mismatch");
            assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(caller));
            assertEq(identityRegistry.tokenURI(agentId), "", "URI should be empty");
        }

        assertEq(identityRegistry.balanceOf(caller), count, "Final balance mismatch");
    }

    function test_register_toContractWithReceiver() public {
        MockERC721Receiver receiver = new MockERC721Receiver();

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(receiver), 0);

        vm.prank(address(receiver));
        uint256 agentId = identityRegistry.register();

        assertEq(identityRegistry.ownerOf(agentId), address(receiver));
        assertEq(identityRegistry.getAgentWallet(agentId), address(receiver));
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(receiver));
    }

    function test_register_revertsForNonReceiver() public {
        NonReceiver nonReceiver = new NonReceiver();
        
        vm.prank(address(nonReceiver));
        vm.expectRevert();
        identityRegistry.register();
    }

    // ============================================================
    // register(string)
    // ============================================================

    function test_registerWithURI(address caller, string calldata uri) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);

        vm.expectEmit(true, true, false, true);
        emit Registered(0, uri, caller);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), caller, 0);

        vm.prank(caller);
        uint256 agentId = identityRegistry.register(uri);

        assertEq(agentId, 0, "First agentId should be 0");
        assertEq(identityRegistry.ownerOf(agentId), caller, "Owner mismatch");
        assertEq(identityRegistry.getAgentWallet(agentId), caller, "AgentWallet mismatch");
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(caller));
        assertEq(identityRegistry.balanceOf(caller), 1, "Balance mismatch");
        assertEq(identityRegistry.tokenURI(agentId), uri, "URI mismatch");
    }

    // ============================================================
    // register(string, MetadataEntry[])
    // ============================================================

    function test_registerWithMetadata(
        address caller,
        string calldata uri,
        string calldata metadataKey,
        bytes calldata metadataValue
    ) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata = 
            new IdentityRegistryUpgradeable.MetadataEntry[](1);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry({
            metadataKey: metadataKey,
            metadataValue: metadataValue
        });

        vm.expectEmit(true, true, false, true);
        emit Registered(0, uri, caller);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(0, metadataKey, metadataKey, metadataValue);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), caller, 0);

        vm.prank(caller);
        uint256 agentId = identityRegistry.register(uri, metadata);

        assertEq(agentId, 0, "First agentId should be 0");
        assertEq(identityRegistry.ownerOf(agentId), caller, "Owner mismatch");
        assertEq(identityRegistry.getAgentWallet(agentId), caller, "AgentWallet mismatch");
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(caller));
        assertEq(identityRegistry.tokenURI(agentId), uri, "URI mismatch");
        assertEq(identityRegistry.getMetadata(agentId, metadataKey), metadataValue, "Metadata mismatch");
    }

    function test_registerWithMetadata_multipleEntries(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata = 
            new IdentityRegistryUpgradeable.MetadataEntry[](3);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("key1", "value1");
        metadata[1] = IdentityRegistryUpgradeable.MetadataEntry("key2", "value2");
        metadata[2] = IdentityRegistryUpgradeable.MetadataEntry("key3", "value3");

        vm.prank(caller);
        uint256 agentId = identityRegistry.register("ipfs://test", metadata);

        assertEq(identityRegistry.getMetadata(agentId, "key1"), bytes("value1"));
        assertEq(identityRegistry.getMetadata(agentId, "key2"), bytes("value2"));
        assertEq(identityRegistry.getMetadata(agentId, "key3"), bytes("value3"));
    }

    function test_registerWithMetadata_emptyArray(address caller, string calldata uri) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata = 
            new IdentityRegistryUpgradeable.MetadataEntry[](0);

        vm.prank(caller);
        uint256 agentId = identityRegistry.register(uri, metadata);

        assertEq(identityRegistry.ownerOf(agentId), caller);
        assertEq(identityRegistry.tokenURI(agentId), uri);
        assertEq(identityRegistry.getAgentWallet(agentId), caller);
    }

    function test_registerWithMetadata_revertsOnReservedKey(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);

        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata = 
            new IdentityRegistryUpgradeable.MetadataEntry[](1);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("agentWallet", "badvalue");

        vm.prank(caller);
        vm.expectRevert("reserved key");
        identityRegistry.register("ipfs://test", metadata);
    }

    // ============================================================
    // setMetadata() - Authorization paths
    // ============================================================

    function test_setMetadata_byOwner(
        string calldata metadataKey,
        bytes calldata metadataValue
    ) public {
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        uint256 agentId = _registerAgent(alice);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);

        vm.prank(alice);
        identityRegistry.setMetadata(agentId, metadataKey, metadataValue);

        assertEq(identityRegistry.getMetadata(agentId, metadataKey), metadataValue);
    }

    function test_setMetadata_byOperator(
        string calldata metadataKey,
        bytes calldata metadataValue
    ) public {
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);

        vm.prank(bob);
        identityRegistry.setMetadata(agentId, metadataKey, metadataValue);

        assertEq(identityRegistry.getMetadata(agentId, metadataKey), metadataValue);
    }

    function test_setMetadata_byApproved(
        string calldata metadataKey,
        bytes calldata metadataValue
    ) public {
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(charlie, agentId);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, metadataKey, metadataKey, metadataValue);

        vm.prank(charlie);
        identityRegistry.setMetadata(agentId, metadataKey, metadataValue);

        assertEq(identityRegistry.getMetadata(agentId, metadataKey), metadataValue);
    }

    function test_setMetadata_overwritesExisting(string calldata metadataKey) public {
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setMetadata(agentId, metadataKey, "firstValue");
        assertEq(identityRegistry.getMetadata(agentId, metadataKey), bytes("firstValue"));

        vm.prank(alice);
        identityRegistry.setMetadata(agentId, metadataKey, "secondValue");
        assertEq(identityRegistry.getMetadata(agentId, metadataKey), bytes("secondValue"));
    }

    function test_setMetadata_revertsWhenNotAuthorized(
        address unauthorized,
        string calldata metadataKey,
        bytes calldata metadataValue
    ) public {
        vm.assume(unauthorized != alice);
        vm.assume(unauthorized != address(0));
        vm.assume(keccak256(bytes(metadataKey)) != keccak256("agentWallet"));

        uint256 agentId = _registerAgent(alice);

        vm.prank(unauthorized);
        vm.expectRevert("Not authorized");
        identityRegistry.setMetadata(agentId, metadataKey, metadataValue);
    }

    function test_setMetadata_revertsOnReservedKey(bytes calldata metadataValue) public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        vm.expectRevert("reserved key");
        identityRegistry.setMetadata(agentId, "agentWallet", metadataValue);
    }

    // ============================================================
    // setAgentURI() - Authorization paths
    // ============================================================

    function test_setAgentURI_byOwner(string calldata newURI) public {
        uint256 agentId = _registerAgent(alice);

        vm.expectEmit(true, false, true, true);
        emit URIUpdated(agentId, newURI, alice);

        vm.prank(alice);
        identityRegistry.setAgentURI(agentId, newURI);

        assertEq(identityRegistry.tokenURI(agentId), newURI);
    }

    function test_setAgentURI_byOperator(string calldata newURI) public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        vm.expectEmit(true, false, true, true);
        emit URIUpdated(agentId, newURI, bob);

        vm.prank(bob);
        identityRegistry.setAgentURI(agentId, newURI);

        assertEq(identityRegistry.tokenURI(agentId), newURI);
    }

    function test_setAgentURI_byApproved(string calldata newURI) public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(charlie, agentId);

        vm.expectEmit(true, false, true, true);
        emit URIUpdated(agentId, newURI, charlie);

        vm.prank(charlie);
        identityRegistry.setAgentURI(agentId, newURI);

        assertEq(identityRegistry.tokenURI(agentId), newURI);
    }

    function test_setAgentURI_revertsWhenNotAuthorized(
        address unauthorized,
        string calldata newURI
    ) public {
        vm.assume(unauthorized != alice);
        vm.assume(unauthorized != address(0));

        uint256 agentId = _registerAgent(alice);

        vm.prank(unauthorized);
        vm.expectRevert("Not authorized");
        identityRegistry.setAgentURI(agentId, newURI);
    }

    function test_setAgentURI_revertsForNonexistentToken(
        uint256 agentId,
        string calldata newURI
    ) public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, agentId));
        identityRegistry.setAgentURI(agentId, newURI);
    }

    // ============================================================
    // getAgentWallet()
    // ============================================================

    function test_getAgentWallet(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(caller.code.length == 0);

        vm.prank(caller);
        uint256 agentId = identityRegistry.register();

        assertEq(identityRegistry.getAgentWallet(agentId), caller);
    }

    function test_getAgentWallet_revertsForNonexistentToken(uint256 agentId) public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, agentId));
        identityRegistry.getAgentWallet(agentId);
    }

    // ============================================================
    // setAgentWallet() - EOA signature verification
    // ============================================================

    function test_setAgentWallet_EOA_byOwner(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);
        vm.assume(newWallet != alice);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));

        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);

        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(newWallet));
    }

    function test_setAgentWallet_EOA_byOperator(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);
        vm.assume(newWallet != alice && newWallet != bob);

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        uint256 deadline = block.timestamp + 1 minutes;
        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));

        vm.prank(bob);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);

        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(newWallet));
    }

    function test_setAgentWallet_EOA_byApproved(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);
        vm.assume(newWallet != alice && newWallet != charlie);

        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(charlie, agentId);

        uint256 deadline = block.timestamp + 1 minutes;
        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(newWallet));

        vm.prank(charlie);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);

        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(newWallet));
    }

    function test_setAgentWallet_EOA_revertsOnInvalidSignature(uint256 newWalletPk, uint256 wrongPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(newWalletPk != wrongPk);
        
        address newWallet = vm.addr(newWalletPk);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes memory signature = _signAgentWallet(wrongPk, agentId, newWallet, alice, deadline);

        vm.prank(alice);
        vm.expectRevert("invalid wallet sig");
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    // ============================================================
    // setAgentWallet() - ERC1271 signature verification
    // ============================================================

    function test_setAgentWallet_ERC1271_byOwner() public {
        MockERC1271Wallet scWallet = new MockERC1271Wallet();
        
        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH,
            agentId,
            address(scWallet),
            alice,
            deadline
        ));
        bytes32 digest = _getDigest(structHash);
        
        scWallet.setExpectedHash(digest);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(address(scWallet)));

        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId, address(scWallet), deadline, "");

        assertEq(identityRegistry.getAgentWallet(agentId), address(scWallet));
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(address(scWallet)));
    }

    function test_setAgentWallet_ERC1271_byOperator() public {
        MockERC1271Wallet scWallet = new MockERC1271Wallet();
        
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        uint256 deadline = block.timestamp + 1 minutes;

        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH,
            agentId,
            address(scWallet),
            alice,
            deadline
        ));
        bytes32 digest = _getDigest(structHash);
        
        scWallet.setExpectedHash(digest);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(address(scWallet)));

        vm.prank(bob);
        identityRegistry.setAgentWallet(agentId, address(scWallet), deadline, "");

        assertEq(identityRegistry.getAgentWallet(agentId), address(scWallet));
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(address(scWallet)));
    }

    function test_setAgentWallet_ERC1271_byApproved() public {
        MockERC1271Wallet scWallet = new MockERC1271Wallet();
        
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(charlie, agentId);

        uint256 deadline = block.timestamp + 1 minutes;

        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH,
            agentId,
            address(scWallet),
            alice,
            deadline
        ));
        bytes32 digest = _getDigest(structHash);
        
        scWallet.setExpectedHash(digest);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", abi.encodePacked(address(scWallet)));

        vm.prank(charlie);
        identityRegistry.setAgentWallet(agentId, address(scWallet), deadline, "");

        assertEq(identityRegistry.getAgentWallet(agentId), address(scWallet));
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), abi.encodePacked(address(scWallet)));
    }

    function test_setAgentWallet_ERC1271_revertsOnInvalidSignature() public {
        MockERC1271Wallet scWallet = new MockERC1271Wallet();
        
        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        scWallet.setShouldSucceed(false);

        vm.prank(alice);
        vm.expectRevert("invalid wallet sig");
        identityRegistry.setAgentWallet(agentId, address(scWallet), deadline, "");
    }

    // ============================================================
    // setAgentWallet() - Input validation
    // ============================================================

    function test_setAgentWallet_revertsWhenNotAuthorized(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.prank(malicious);
        vm.expectRevert("Not authorized");
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function test_setAgentWallet_revertsOnZeroAddress() public {
        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        vm.prank(alice);
        vm.expectRevert("bad wallet");
        identityRegistry.setAgentWallet(agentId, address(0), deadline, "");
    }

    function test_setAgentWallet_revertsWhenExpired(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp - 1;

        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.prank(alice);
        vm.expectRevert("expired");
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function test_setAgentWallet_revertsWhenDeadlineTooFar(uint256 newWalletPk) public {
        newWalletPk = bound(newWalletPk, 1, type(uint128).max);
        address newWallet = vm.addr(newWalletPk);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + MAX_DEADLINE_DELAY + 1;

        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.prank(alice);
        vm.expectRevert("deadline too far");
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
    }

    function test_setAgentWallet_exactDeadlineBoundaries() public {
        uint256 newWalletPk = 12345;
        address newWallet = vm.addr(newWalletPk);
        
        uint256 agentId = _registerAgent(alice);

        // Test deadline exactly at current timestamp (boundary: <=)
        uint256 deadline1 = block.timestamp;
        bytes memory sig1 = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline1);
        
        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline1, sig1);
        assertEq(identityRegistry.getAgentWallet(agentId), newWallet);

        // Reset and test deadline exactly at max delay (boundary: <=)
        uint256 agentId2 = _registerAgent(alice);
        uint256 newWalletPk2 = 12346;
        address newWallet2 = vm.addr(newWalletPk2);
        uint256 deadline2 = block.timestamp + MAX_DEADLINE_DELAY;
        bytes memory sig2 = _signAgentWallet(newWalletPk2, agentId2, newWallet2, alice, deadline2);

        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId2, newWallet2, deadline2, sig2);
        assertEq(identityRegistry.getAgentWallet(agentId2), newWallet2);
    }

    // ============================================================
    // Transfer - agentWallet reset behavior
    // ============================================================

    function test_transferFrom_resetsAgentWallet(address newOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != alice);
        vm.assume(newOwner.code.length == 0);

        uint256 agentId = _registerAgent(alice);
        assertEq(identityRegistry.getAgentWallet(agentId), alice);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, newOwner, agentId);

        vm.expectEmit(true, true, false, true);
        emit MetadataSet(agentId, "agentWallet", "agentWallet", "");

        vm.prank(alice);
        identityRegistry.transferFrom(alice, newOwner, agentId);

        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
        assertEq(identityRegistry.getMetadata(agentId, "agentWallet"), "");
        assertEq(identityRegistry.ownerOf(agentId), newOwner);
    }

    function test_transferFrom_byOperator() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setApprovalForAll(bob, true);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, agentId);

        vm.prank(bob);
        identityRegistry.transferFrom(alice, charlie, agentId);

        assertEq(identityRegistry.ownerOf(agentId), charlie);
        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
    }

    function test_transferFrom_byApproved() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.approve(bob, agentId);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, charlie, agentId);

        vm.prank(bob);
        identityRegistry.transferFrom(alice, charlie, agentId);

        assertEq(identityRegistry.ownerOf(agentId), charlie);
        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
    }

    function test_safeTransferFrom_resetsAgentWallet() public {
        uint256 agentId = _registerAgent(alice);
        MockERC721Receiver receiver = new MockERC721Receiver();

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(receiver), agentId);

        vm.prank(alice);
        identityRegistry.safeTransferFrom(alice, address(receiver), agentId);

        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
        assertEq(identityRegistry.ownerOf(agentId), address(receiver));
    }

    function test_safeTransferFrom_withData_resetsAgentWallet() public {
        uint256 agentId = _registerAgent(alice);
        MockERC721Receiver receiver = new MockERC721Receiver();

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(receiver), agentId);

        vm.prank(alice);
        identityRegistry.safeTransferFrom(alice, address(receiver), agentId, "some data");

        assertEq(identityRegistry.getAgentWallet(agentId), address(0));
        assertEq(identityRegistry.ownerOf(agentId), address(receiver));
    }

    function test_selfTransfer_doesntClearAgentWallet() public {
        // Known behavior: self-transfer doesn't clear agentWallet
        uint256 agentId = _registerAgent(alice);
        assertEq(identityRegistry.getAgentWallet(agentId), alice);

        vm.prank(alice);
        identityRegistry.transferFrom(alice, alice, agentId);

        assertEq(identityRegistry.getAgentWallet(agentId), alice);
        assertEq(identityRegistry.ownerOf(agentId), alice);
    }

    // ============================================================
    // Gas Profiling Tests
    // ============================================================

    function test_register_gas() public {
        vm.prank(alice);
        identityRegistry.register();
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "register()");
    }

    function test_registerWithURI_gas() public {
        vm.prank(alice);
        identityRegistry.register("ipfs://QmTest");
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "register(string)");
    }

    function test_registerWithMetadata_gas() public {
        IdentityRegistryUpgradeable.MetadataEntry[] memory metadata = 
            new IdentityRegistryUpgradeable.MetadataEntry[](1);
        metadata[0] = IdentityRegistryUpgradeable.MetadataEntry("key", "value");

        vm.prank(alice);
        identityRegistry.register("ipfs://QmTest", metadata);
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "register(string,MetadataEntry[])");
    }

    function test_getMetadata_gas() public {
        uint256 agentId = _registerAgent(alice);
        
        vm.prank(alice);
        identityRegistry.setMetadata(agentId, "testKey", "testValue");

        identityRegistry.getMetadata(agentId, "testKey");
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "getMetadata");
    }

    function test_setMetadata_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setMetadata(agentId, "testKey", "testValue");
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "setMetadata");
    }

    function test_setAgentURI_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.setAgentURI(agentId, "ipfs://QmNewURI");
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "setAgentURI");
    }

    function test_getAgentWallet_gas() public {
        uint256 agentId = _registerAgent(alice);

        identityRegistry.getAgentWallet(agentId);
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "getAgentWallet");
    }

    function test_setAgentWallet_EOA_gas() public {
        uint256 newWalletPk = 12345;
        address newWallet = vm.addr(newWalletPk);

        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes memory signature = _signAgentWallet(newWalletPk, agentId, newWallet, alice, deadline);

        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId, newWallet, deadline, signature);
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "setAgentWallet(EOA)");
    }

    function test_setAgentWallet_ERC1271_gas() public {
        MockERC1271Wallet scWallet = new MockERC1271Wallet();
        
        uint256 agentId = _registerAgent(alice);
        uint256 deadline = block.timestamp + 1 minutes;

        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH,
            agentId,
            address(scWallet),
            alice,
            deadline
        ));
        bytes32 digest = _getDigest(structHash);
        
        scWallet.setExpectedHash(digest);

        vm.prank(alice);
        identityRegistry.setAgentWallet(agentId, address(scWallet), deadline, "");
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "setAgentWallet(ERC1271)");
    }

    function test_transferFrom_gas() public {
        uint256 agentId = _registerAgent(alice);

        vm.prank(alice);
        identityRegistry.transferFrom(alice, bob, agentId);
        vm.snapshotGasLastCall("IdentityRegistryUpgradeable", "transferFrom");
    }

    // ============================================================
    // Internal Helpers
    // ============================================================

    function _signAgentWallet(
        uint256 signerPk,
        uint256 agentId,
        address newWallet,
        address agentOwner,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(
            AGENT_WALLET_SET_TYPEHASH,
            agentId,
            newWallet,
            agentOwner,
            deadline
        ));
        bytes32 digest = _getDigest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _getDigest(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("ERC8004IdentityRegistry"),
            keccak256("1"),
            block.chainid,
            address(identityRegistry)
        ));
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }
}
