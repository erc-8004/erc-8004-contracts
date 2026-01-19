import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { encodeAbiParameters, keccak256, toHex } from "viem";

describe("ERC8004 Upgradeable Registries", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  // Helper function to extract agentId from Registered event
  async function getAgentIdFromRegistration(txHash: `0x${string}`) {
    const receipt = await publicClient.getTransactionReceipt({ hash: txHash });
    const registeredLog = receipt.logs.find(log => log.topics[0] === keccak256(toHex("Registered(uint256,string,address)")));
    if (!registeredLog || !registeredLog.topics[1]) {
      throw new Error("Registered event not found");
    }
    return BigInt(registeredLog.topics[1]);
  }

  // Helper to deploy a proxy with initialization
  async function deployProxy(implementationAddress: `0x${string}`, initCalldata: `0x${string}`) {
    return await viem.deployContract("ERC1967Proxy", [implementationAddress, initCalldata]);
  }

  // Helper to encode initialize() with no parameters
  function encodeInitialize(): `0x${string}` {
    return "0x8129fc1c";
  }

  // Helper to encode initialize(address) with one parameter
  function encodeInitializeWithAddress(identityRegistry: `0x${string}`): `0x${string}` {
    const params = encodeAbiParameters([{ type: "address" }], [identityRegistry]);
    return ("0xc4d66de8" + params.slice(2)) as `0x${string}`;
  }

  // Helper to deploy IdentityRegistry proxy via HardhatMinimalUUPS -> upgrade pattern
  async function deployIdentityRegistryProxy() {
    const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
    const minimalInitCalldata = encodeInitializeWithAddress("0x0000000000000000000000000000000000000000");
    const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);

    const realImpl = await viem.deployContract("IdentityRegistryUpgradeable");
    const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
    await minimalProxy.write.upgradeToAndCall([realImpl.address, encodeInitialize()]);

    return await viem.getContractAt("IdentityRegistryUpgradeable", proxy.address);
  }

  // Helper to deploy ReputationRegistry proxy via HardhatMinimalUUPS -> upgrade pattern
  async function deployReputationRegistryProxy(identityRegistryAddress: `0x${string}`) {
    const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
    const minimalInitCalldata = encodeInitializeWithAddress(identityRegistryAddress);
    const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);

    const realImpl = await viem.deployContract("ReputationRegistryUpgradeable");
    const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
    const reinitCalldata = encodeInitializeWithAddress(identityRegistryAddress);
    await minimalProxy.write.upgradeToAndCall([realImpl.address, reinitCalldata]);

    return await viem.getContractAt("ReputationRegistryUpgradeable", proxy.address);
  }

  // Helper to deploy ValidationRegistry proxy via HardhatMinimalUUPS -> upgrade pattern
  async function deployValidationRegistryProxy(identityRegistryAddress: `0x${string}`) {
    const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
    const minimalInitCalldata = encodeInitializeWithAddress(identityRegistryAddress);
    const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);

    const realImpl = await viem.deployContract("ValidationRegistryUpgradeable");
    const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
    const reinitCalldata = encodeInitializeWithAddress(identityRegistryAddress);
    await minimalProxy.write.upgradeToAndCall([realImpl.address, reinitCalldata]);

    return await viem.getContractAt("ValidationRegistryUpgradeable", proxy.address);
  }

  describe("IdentityRegistryUpgradeable", async function () {
    it("Should deploy through proxy and initialize", async function () {
      const [owner] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      // Verify initialization
      const version = await identityRegistry.read.getVersion();
      assert.equal(version, "2.0.0");

      // Verify owner
      const contractOwner = await identityRegistry.read.owner();
      assert.equal(contractOwner.toLowerCase(), owner.account.address.toLowerCase());
    });

    it("Should prevent double initialization", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();

      // Try to initialize again
      await assert.rejects(
        identityRegistry.write.initialize()
      );
    });

    it("Should maintain functionality through proxy", async function () {
      const [owner] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      // Test register function
      const tokenURI = "ipfs://QmTest123";
      const txHash = await identityRegistry.write.register([tokenURI]);
      const agentId = await getAgentIdFromRegistration(txHash);

      // Verify tokenURI
      const retrievedURI = await identityRegistry.read.tokenURI([agentId]);
      assert.equal(retrievedURI, tokenURI);

      // Verify owner
      const tokenOwner = await identityRegistry.read.ownerOf([agentId]);
      assert.equal(tokenOwner.toLowerCase(), owner.account.address.toLowerCase());
    });

    it("Should upgrade to new implementation", async function () {
      const [owner] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      // Register an agent
      const tokenURI = "ipfs://v1-agent";
      const txHash = await identityRegistry.write.register([tokenURI]);
      const agentId = await getAgentIdFromRegistration(txHash);

      // Deploy V2 (same contract for this test, in real scenario would be upgraded version)
      const implV2 = await viem.deployContract("IdentityRegistryUpgradeable");

      // Upgrade
      await identityRegistry.write.upgradeToAndCall([implV2.address, "0x"]);

      // Verify data persists after upgrade
      const retrievedURI = await identityRegistry.read.tokenURI([agentId]);
      assert.equal(retrievedURI, tokenURI);

      const tokenOwner = await identityRegistry.read.ownerOf([agentId]);
      assert.equal(tokenOwner.toLowerCase(), owner.account.address.toLowerCase());

      // Verify can still register new agents
      const newTxHash = await identityRegistry.write.register(["ipfs://v2-agent"]);
      const newAgentId = await getAgentIdFromRegistration(newTxHash);
      assert.ok(newAgentId > agentId);
    });

    it("Should only allow owner to upgrade", async function () {
      const [owner, attacker] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      const implV2 = await viem.deployContract("IdentityRegistryUpgradeable");

      // Attacker tries to upgrade
      await assert.rejects(
        identityRegistry.write.upgradeToAndCall(
          [implV2.address, "0x"],
          { account: attacker.account }
        )
      );
    });
  });

  describe("ReputationRegistryUpgradeable", async function () {
    it("Should deploy through proxy with identityRegistry", async function () {
      const [owner] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();
      const reputationRegistry = await deployReputationRegistryProxy(identityRegistry.address);

      // Verify initialization
      const version = await reputationRegistry.read.getVersion();
      assert.equal(version, "2.0.0");

      const storedIdentityRegistry = await reputationRegistry.read.getIdentityRegistry();
      assert.equal(storedIdentityRegistry.toLowerCase(), identityRegistry.address.toLowerCase());
    });

    it("Should upgrade and maintain storage", async function () {
      const [owner, client] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      // Register an agent
      const txHash = await identityRegistry.write.register(["ipfs://agent"]);
      const agentId = await getAgentIdFromRegistration(txHash);

      const reputationRegistry = await deployReputationRegistryProxy(identityRegistry.address);

      // Give feedback
      await reputationRegistry.write.giveFeedback(
        [agentId, 95, 0, "quality", "service", "https://agent.endpoint.com", "ipfs://feedback", keccak256(toHex("content"))],
        { account: client.account }
      );

      // Upgrade to V2
      const reputationImplV2 = await viem.deployContract("ReputationRegistryUpgradeable");
      await reputationRegistry.write.upgradeToAndCall([reputationImplV2.address, "0x"]);

      // Verify feedback persists
      const feedback = await reputationRegistry.read.readFeedback([agentId, client.account.address, 1n]);
      assert.equal(feedback[0], 95n); // score
    });
  });

  describe("ValidationRegistryUpgradeable", async function () {
    it("Should deploy through proxy with identityRegistry", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const validationRegistry = await deployValidationRegistryProxy(identityRegistry.address);

      // Verify initialization
      const version = await validationRegistry.read.getVersion();
      assert.equal(version, "2.0.0");

      const storedIdentityRegistry = await validationRegistry.read.getIdentityRegistry();
      assert.equal(storedIdentityRegistry.toLowerCase(), identityRegistry.address.toLowerCase());
    });

    it("Should upgrade and maintain validation data", async function () {
      const [owner, validator] = await viem.getWalletClients();

      const identityRegistry = await deployIdentityRegistryProxy();

      // Register an agent
      const txHash = await identityRegistry.write.register(["ipfs://agent"]);
      const agentId = await getAgentIdFromRegistration(txHash);

      const validationRegistry = await deployValidationRegistryProxy(identityRegistry.address);

      // Create validation request
      const requestHash = keccak256(toHex("request data"));
      await validationRegistry.write.validationRequest([
        validator.account.address,
        agentId,
        "ipfs://request",
        requestHash
      ]);

      // Submit response
      await validationRegistry.write.validationResponse(
        [requestHash, 100, "ipfs://response", keccak256(toHex("response")), keccak256(toHex("passed"))],
        { account: validator.account }
      );

      // Upgrade to V2
      const validationImplV2 = await viem.deployContract("ValidationRegistryUpgradeable");
      await validationRegistry.write.upgradeToAndCall([validationImplV2.address, "0x"]);

      // Verify validation data persists
      const status = await validationRegistry.read.getValidationStatus([requestHash]);
      assert.equal(status[0].toLowerCase(), validator.account.address.toLowerCase());
      assert.equal(status[1], agentId);
      assert.equal(status[2], 100); // response
    });
  });

  describe("Full Integration Test with Upgrades", async function () {
    it("Should deploy all registries, use them, and upgrade all", async function () {
      const [owner, client, validator] = await viem.getWalletClients();

      // Deploy all three registries
      const identityRegistry = await deployIdentityRegistryProxy();
      const reputationRegistry = await deployReputationRegistryProxy(identityRegistry.address);
      const validationRegistry = await deployValidationRegistryProxy(identityRegistry.address);

      // Use the registries
      const txHash = await identityRegistry.write.register(["ipfs://test-agent"]);
      const agentId = await getAgentIdFromRegistration(txHash);

      // Upgrade all three registries
      const identityImplV2 = await viem.deployContract("IdentityRegistryUpgradeable");
      const reputationImplV2 = await viem.deployContract("ReputationRegistryUpgradeable");
      const validationImplV2 = await viem.deployContract("ValidationRegistryUpgradeable");

      await identityRegistry.write.upgradeToAndCall([identityImplV2.address, "0x"]);
      await reputationRegistry.write.upgradeToAndCall([reputationImplV2.address, "0x"]);
      await validationRegistry.write.upgradeToAndCall([validationImplV2.address, "0x"]);

      // Verify data persists and functionality works
      const tokenURI = await identityRegistry.read.tokenURI([agentId]);
      assert.equal(tokenURI, "ipfs://test-agent");

      // Can still register new agents
      const newTxHash = await identityRegistry.write.register(["ipfs://post-upgrade-agent"]);
      const newAgentId = await getAgentIdFromRegistration(newTxHash);
      assert.ok(newAgentId > agentId);
    });
  });

  describe("Critical Security Tests", async function () {
    describe("Initialization Security", async function () {
      it("Should prevent direct initialization of implementation contract", async function () {
        // Deploy implementation (not through proxy)
        const impl = await viem.deployContract("IdentityRegistryUpgradeable");

        // Try to get contract instance at implementation address
        const implAsContract = await viem.getContractAt("IdentityRegistryUpgradeable", impl.address);

        // Try to initialize implementation directly (should fail due to _disableInitializers)
        await assert.rejects(
          implAsContract.write.initialize(),
          /InvalidInitialization/,
          "Implementation should not be initializable directly"
        );
      });

      it("Should prevent initialization with zero address for registries", async function () {
        // Deploy HardhatMinimalUUPS first, then try to upgrade to ReputationRegistry with zero address
        const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
        const zeroAddress = "0x0000000000000000000000000000000000000000" as `0x${string}`;
        const minimalInitCalldata = encodeInitializeWithAddress(zeroAddress);
        const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);

        const reputationImpl = await viem.deployContract("ReputationRegistryUpgradeable");
        const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
        const reinitCalldata = encodeInitializeWithAddress(zeroAddress);

        await assert.rejects(
          minimalProxy.write.upgradeToAndCall([reputationImpl.address, reinitCalldata]),
          /bad identity/,
          "Should reject zero address for identityRegistry"
        );
      });
    });

    describe("Upgrade Authorization", async function () {
      it("Should reject upgrade to zero address", async function () {
        const registry = await deployIdentityRegistryProxy();

        const zeroAddress = "0x0000000000000000000000000000000000000000" as `0x${string}`;

        await assert.rejects(
          registry.write.upgradeToAndCall([zeroAddress, "0x"]),
          "Should reject upgrade to zero address"
        );
      });

      it("Should reject upgrade to non-contract address", async function () {
        const [_, randomUser] = await viem.getWalletClients();

        const registry = await deployIdentityRegistryProxy();

        // Try to upgrade to an EOA (Externally Owned Account)
        await assert.rejects(
          registry.write.upgradeToAndCall([randomUser.account.address, "0x"]),
          "Should reject upgrade to non-contract address"
        );
      });

      it("Should handle ownership transfer and upgrade permissions correctly", async function () {
        const [owner, newOwner, attacker] = await viem.getWalletClients();

        const registry = await deployIdentityRegistryProxy();

        // Register some data
        const txHash = await registry.write.register(["ipfs://agent"]);
        const agentId = await getAgentIdFromRegistration(txHash);

        // Transfer ownership to newOwner
        await registry.write.transferOwnership([newOwner.account.address]);

        // Verify ownership transferred
        const currentOwner = await registry.read.owner();
        assert.equal(currentOwner.toLowerCase(), newOwner.account.address.toLowerCase());

        const implV2 = await viem.deployContract("IdentityRegistryUpgradeable");

        // Old owner should NOT be able to upgrade
        await assert.rejects(
          registry.write.upgradeToAndCall([implV2.address, "0x"], { account: owner.account }),
          /OwnableUnauthorizedAccount/,
          "Old owner should not be able to upgrade"
        );

        // Attacker should NOT be able to upgrade
        await assert.rejects(
          registry.write.upgradeToAndCall([implV2.address, "0x"], { account: attacker.account }),
          /OwnableUnauthorizedAccount/,
          "Attacker should not be able to upgrade"
        );

        // New owner SHOULD be able to upgrade
        await registry.write.upgradeToAndCall([implV2.address, "0x"], { account: newOwner.account });

        // Verify data persisted after upgrade
        const uri = await registry.read.tokenURI([agentId]);
        assert.equal(uri, "ipfs://agent");

        // Verify ownership still correct
        const ownerAfterUpgrade = await registry.read.owner();
        assert.equal(ownerAfterUpgrade.toLowerCase(), newOwner.account.address.toLowerCase());
      });
    });

    describe("Storage Collision Prevention", async function () {
      it("Should maintain complex storage across upgrades", async function () {
        const [owner] = await viem.getWalletClients();

        const registry = await deployIdentityRegistryProxy();

        // Create multiple agents with different data
        const agents = [];
        for (let i = 0; i < 5; i++) {
          const txHash = await registry.write.register([`ipfs://agent-${i}`]);
          const agentId = await getAgentIdFromRegistration(txHash);
          agents.push(agentId);
        }

        // Store metadata for different agents
        await registry.write.setMetadata([agents[0], "key1", toHex("value1")]);
        await registry.write.setMetadata([agents[0], "key2", toHex("value2")]);
        await registry.write.setMetadata([agents[1], "key1", toHex("different-value")]);
        await registry.write.setMetadata([agents[2], "special", toHex("special-data")]);

        // Upgrade to V2
        const implV2 = await viem.deployContract("IdentityRegistryUpgradeable");
        await registry.write.upgradeToAndCall([implV2.address, "0x"]);

        // Verify ALL agents persist with correct URIs
        for (let i = 0; i < agents.length; i++) {
          const uri = await registry.read.tokenURI([agents[i]]);
          assert.equal(uri, `ipfs://agent-${i}`, `Agent ${i} URI should persist`);
        }

        // Verify ALL metadata persists correctly
        const meta1 = await registry.read.getMetadata([agents[0], "key1"]);
        const meta2 = await registry.read.getMetadata([agents[0], "key2"]);
        const meta3 = await registry.read.getMetadata([agents[1], "key1"]);
        const meta4 = await registry.read.getMetadata([agents[2], "special"]);

        assert.equal(meta1, toHex("value1"));
        assert.equal(meta2, toHex("value2"));
        assert.equal(meta3, toHex("different-value"));
        assert.equal(meta4, toHex("special-data"));

        // Verify can still add new agents and metadata after upgrade
        const newTxHash = await registry.write.register(["ipfs://post-upgrade"]);
        const newAgentId = await getAgentIdFromRegistration(newTxHash);
        await registry.write.setMetadata([newAgentId, "new-key", toHex("new-value")]);

        const newMeta = await registry.read.getMetadata([newAgentId, "new-key"]);
        assert.equal(newMeta, toHex("new-value"));
      });

      it("Should preserve nested mapping storage across upgrades", async function () {
        const [owner, client1, client2] = await viem.getWalletClients();

        // Deploy both registries
        const identityRegistry = await deployIdentityRegistryProxy();
        const reputationRegistry = await deployReputationRegistryProxy(identityRegistry.address);

        // Register agents
        const txHash1 = await identityRegistry.write.register(["ipfs://agent1"]);
        const agentId1 = await getAgentIdFromRegistration(txHash1);

        const txHash2 = await identityRegistry.write.register(["ipfs://agent2"]);
        const agentId2 = await getAgentIdFromRegistration(txHash2);

        // Create multiple feedbacks with complex data
        // Helper to create feedback
        async function giveFeedback(agentId: bigint, client: any, score: number, category: string) {
          await reputationRegistry.write.giveFeedback(
            [agentId, score, 0, category, "service", "https://agent.endpoint.com", `ipfs://feedback-${category}`, keccak256(toHex("content"))],
            { account: client.account }
          );
        }

        // Create feedback matrix: 2 agents × 2 clients = 4 feedbacks
        await giveFeedback(agentId1, client1, 85, "quality");
        await giveFeedback(agentId1, client2, 90, "speed");
        await giveFeedback(agentId2, client1, 75, "quality");
        await giveFeedback(agentId2, client2, 95, "reliability");

        // Upgrade reputation registry
        const reputationImplV2 = await viem.deployContract("ReputationRegistryUpgradeable");
        await reputationRegistry.write.upgradeToAndCall([reputationImplV2.address, "0x"]);

        // Verify ALL feedbacks persist with correct nested mapping structure
        const feedback1 = await reputationRegistry.read.readFeedback([agentId1, client1.account.address, 1n]);
        assert.equal(feedback1[0], 85n, "Agent1-Client1 score should persist");

        const feedback2 = await reputationRegistry.read.readFeedback([agentId1, client2.account.address, 1n]);
        assert.equal(feedback2[0], 90n, "Agent1-Client2 score should persist");

        const feedback3 = await reputationRegistry.read.readFeedback([agentId2, client1.account.address, 1n]);
        assert.equal(feedback3[0], 75n, "Agent2-Client1 score should persist");

        const feedback4 = await reputationRegistry.read.readFeedback([agentId2, client2.account.address, 1n]);
        assert.equal(feedback4[0], 95n, "Agent2-Client2 score should persist");
      });
    });

    describe("Upgrade Event Emission", async function () {
      it("Should emit Upgraded event with correct implementation address", async function () {
        const registry = await deployIdentityRegistryProxy();

        const implV2 = await viem.deployContract("IdentityRegistryUpgradeable");
        const txHash = await registry.write.upgradeToAndCall([implV2.address, "0x"]);

        const receipt = await publicClient.getTransactionReceipt({ hash: txHash });

        // Verify Upgraded event was emitted (EIP-1967 standard)
        // Event signature: Upgraded(address indexed implementation)
        const upgradedEventSig = keccak256(toHex("Upgraded(address)"));
        const upgradedEvent = receipt.logs.find(log => log.topics[0] === upgradedEventSig);

        assert.ok(upgradedEvent, "Upgraded event should be emitted");

        // Verify the new implementation address is in the event
        if (upgradedEvent && upgradedEvent.topics[1]) {
          const emittedAddress = `0x${upgradedEvent.topics[1].slice(26)}` as `0x${string}`;
          assert.equal(
            emittedAddress.toLowerCase(),
            implV2.address.toLowerCase(),
            "Event should contain new implementation address"
          );
        }
      });
    });
  });

  });
