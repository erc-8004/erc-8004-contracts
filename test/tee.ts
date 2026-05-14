import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";
import { encodeAbiParameters, getAddress, keccak256, toHex, zeroAddress } from "viem";

/**
 * TEE Key Registry tests — standalone (no validation registry dependency).
 * Tests verifier management (owner-only, with TEEType),
 * key registration (permissionless, with pubKeyBytes support),
 * reverse lookups (identifier → pubKey), key linking to agent IDs,
 * key expiry, and key overwriting.
 */
describe("TEE Key Registry (standalone, with sparsity RI features)", async function () {
  const { viem } = await network.connect();
  const publicClient = await viem.getPublicClient();

  // --- Helpers ---
  function encodeInitialize(): `0x${string}` {
    return "0x8129fc1c";
  }
  function encodeInitializeWithAddress(identityRegistry: `0x${string}`): `0x${string}` {
    const params = encodeAbiParameters([{ type: "address" }], [identityRegistry]);
    return ("0xc4d66de8" + params.slice(2)) as `0x${string}`;
  }
  async function deployProxy(implementationAddress: `0x${string}`, initCalldata: `0x${string}`) {
    return await viem.deployContract("ERC1967Proxy", [implementationAddress, initCalldata]);
  }

  async function deployIdentityRegistryProxy() {
    const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
    const minimalInitCalldata = encodeInitializeWithAddress("0x0000000000000000000000000000000000000000");
    const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);
    const realImpl = await viem.deployContract("IdentityRegistryUpgradeable");
    const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
    await minimalProxy.write.upgradeToAndCall([realImpl.address, encodeInitialize()]);
    return await viem.getContractAt("IdentityRegistryUpgradeable", proxy.address);
  }

  async function deployTEERegistryProxy(identityRegistry: `0x${string}`) {
    const minimalImpl = await viem.deployContract("HardhatMinimalUUPS");
    const minimalInitCalldata = encodeInitializeWithAddress(identityRegistry);
    const proxy = await deployProxy(minimalImpl.address, minimalInitCalldata);
    const realImpl = await viem.deployContract("TEERegistryUpgradeable");
    const minimalProxy = await viem.getContractAt("HardhatMinimalUUPS", proxy.address);
    const reinitCalldata = encodeInitializeWithAddress(identityRegistry);
    await minimalProxy.write.upgradeToAndCall([realImpl.address, reinitCalldata]);
    return await viem.getContractAt("TEERegistryUpgradeable", proxy.address);
  }

  // ===== VERIFIER MANAGEMENT =====

  describe("Verifier management", function () {
    it("should add verifier as owner with TEEType", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 0]); // 0 = TDX
      assert.equal(await teeRegistry.read.isVerifier([verifier.address]), true);
      assert.equal(await teeRegistry.read.getVerifierType([verifier.address]), 0); // TDX
    });

    it("should add verifier as NITRO", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 1]); // 1 = NITRO
      assert.equal(await teeRegistry.read.getVerifierType([verifier.address]), 1); // NITRO
    });

    it("should reject add from non-owner", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const [owner, nonOwner] = await viem.getWalletClients();
      const verifier = await viem.deployContract("MockTEEVerifier", [true]);

      await assert.rejects(
        teeRegistry.write.addVerifier([verifier.address, 0], { account: nonOwner.account }),
        /OwnableUnauthorizedAccount/
      );
    });

    it("should remove verifier and clear type", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 1]);
      await teeRegistry.write.removeVerifier([verifier.address]);
      assert.equal(await teeRegistry.read.isVerifier([verifier.address]), false);
      // getVerifierType returns 0 (TDX) after delete — uint8 zero-value from deleted mapping
      assert.equal(await teeRegistry.read.getVerifierType([verifier.address]), 0);
    });
  });

  // ===== KEY REGISTRATION =====

  describe("Key registration", function () {
    it("should register a TEE-attested key with pubKeyBytes", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, tee] = await viem.getWalletClients();
      const proof = toHex("tee-proof-data");
      const pubKeyBytes = toHex("ed25519-raw-key-data");
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await teeRegistry.write.addKey(
        [proof, tee.account.address, pubKeyBytes, expiration, verifier.address],
        { account: tee.account }
      );

      const [valid, identifiers, expiry, storedVerifier, storedPubKeyBytes] = await teeRegistry.read.getKey([tee.account.address]);
      assert.equal(valid, true);
      assert.equal(expiry, expiration);
      assert.equal(storedVerifier.toLowerCase(), verifier.address.toLowerCase());
      assert.equal(storedPubKeyBytes, pubKeyBytes);
    });

    it("should register key with empty pubKeyBytes", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 1]);

      const [owner, tee] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await teeRegistry.write.addKey(
        [toHex("proof"), tee.account.address, "0x", expiration, verifier.address],
        { account: tee.account }
      );

      const [valid, _ids, _exp, _v, pubKeyBytes] = await teeRegistry.read.getKey([tee.account.address]);
      assert.equal(valid, true);
      assert.equal(pubKeyBytes, "0x");
    });

    it("should reject addKey with unapproved verifier", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const [owner, tee] = await viem.getWalletClients();
      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await assert.rejects(
        teeRegistry.write.addKey(
          [toHex("proof"), tee.account.address, "0x", expiration, verifier.address],
          { account: tee.account }
        ),
        /unapproved verifier/
      );
    });

    it("should reject addKey when verifier returns false", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const [owner, tee] = await viem.getWalletClients();
      const verifier = await viem.deployContract("MockTEEVerifier", [false]);
      await teeRegistry.write.addVerifier([verifier.address, 0]);
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await assert.rejects(
        teeRegistry.write.addKey(
          [toHex("bad-proof"), tee.account.address, "0x", expiration, verifier.address],
          { account: tee.account }
        ),
        /invalid TEE proof/
      );
    });

    it("should return identifiers from verifier", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      const mockId = keccak256(toHex("code-measurement-0xABCD"));
      await verifier.write.setResult([true, [mockId]]);

      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, tee] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await teeRegistry.write.addKey(
        [toHex("proof"), tee.account.address, toHex("key-bytes"), expiration, verifier.address],
        { account: tee.account }
      );

      const [valid, identifiers] = await teeRegistry.read.getKey([tee.account.address]);
      assert.equal(valid, true);
      assert.equal(identifiers.length, 1);
      assert.equal(identifiers[0], mockId);
    });
  });

  // ===== REVERSE LOOKUP =====

  describe("Reverse lookup", function () {
    it("should find pubKey by identifier", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      const mockId = keccak256(toHex("enclave-measurement-123"));
      await verifier.write.setResult([true, [mockId]]);

      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, tee] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      await teeRegistry.write.addKey(
        [toHex("proof"), tee.account.address, "0x", expiration, verifier.address],
        { account: tee.account }
      );

      const pubKey = await teeRegistry.read.getKeyByIdentifier([mockId]);
      assert.equal(pubKey.toLowerCase(), tee.account.address.toLowerCase());
    });
  });

  // ===== EXPIRATION =====

  describe("Key expiration", function () {
    it("should return expired for expired key", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, tee] = await viem.getWalletClients();
      const pastExpiration = BigInt(Math.floor(Date.now() / 1000) - 3600);

      await teeRegistry.write.addKey(
        [toHex("proof"), tee.account.address, "0x", pastExpiration, verifier.address],
        { account: tee.account }
      );

      const [valid] = await teeRegistry.read.getKey([tee.account.address]);
      assert.equal(valid, false);
    });

    it("should return valid for key with zero expiration", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 1]);

      const [owner, tee] = await viem.getWalletClients();

      await teeRegistry.write.addKey(
        [toHex("proof"), tee.account.address, toHex("raw-key"), 0n, verifier.address],
        { account: tee.account }
      );

      const [valid] = await teeRegistry.read.getKey([tee.account.address]);
      assert.equal(valid, true);
    });
  });

  // ===== KEY OVERWRITE =====

  describe("Key overwrite", function () {
    it("should overwrite existing key and update reverse lookups", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);

      const oldId = keccak256(toHex("old-measurement"));
      await verifier.write.setResult([true, [oldId]]);
      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, tee] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // First registration
      await teeRegistry.write.addKey(
        [toHex("proof1"), tee.account.address, toHex("old-key-bytes"), expiration, verifier.address],
        { account: tee.account }
      );

      assert.equal(
        (await teeRegistry.read.getKeyByIdentifier([oldId])).toLowerCase(),
        tee.account.address.toLowerCase()
      );

      // Re-register with new identifier
      const newId = keccak256(toHex("new-measurement"));
      await verifier.write.setResult([true, [newId]]);
      await teeRegistry.write.addKey(
        [toHex("proof2"), tee.account.address, toHex("new-key-bytes"), expiration, verifier.address],
        { account: tee.account }
      );

      assert.equal(
        await teeRegistry.read.getKeyByIdentifier([oldId]),
        zeroAddress
      );
      assert.equal(
        (await teeRegistry.read.getKeyByIdentifier([newId])).toLowerCase(),
        tee.account.address.toLowerCase()
      );
    });
  });

  // ===== SPARSITY TEE VERIFIER ADAPTER =====

  describe("SparsityTEEVerifier adapter", function () {
    it("should verify valid Sparsity-format proof and return identifiers", async function () {
      const mockSparsity = await viem.deployContract("MockSparsityVerifier", [true]);
      const adapter = await viem.deployContract("SparsityTEEVerifier", [mockSparsity.address]);

      const [owner, tee] = await viem.getWalletClients();
      const teeArch = BigInt(1); // NITRO
      const codeMeasurement = keccak256(toHex("pcr-composite-123"));
      const teePubkey = tee.account.address;
      const agentWallet = owner.account.address;

      // Build publicValues: (uint256 teeArch, bytes32 codeMeasurement, address teePubkey, address agentWalletAddress)
      const publicValues = encodeAbiParameters(
        [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }, { type: "address" }],
        [teeArch, codeMeasurement, teePubkey, agentWallet]
      );
      const proofBytes = toHex("zk-proof-data");
      const proof = encodeAbiParameters(
        [{ type: "bytes" }, { type: "bytes" }],
        [publicValues, proofBytes]
      );

      const [success, identifiers] = await adapter.read.verify([proof, teePubkey]);
      assert.equal(success, true);
      assert.equal(identifiers.length, 2);
      assert.equal(identifiers[0], codeMeasurement);
      assert.equal(identifiers[1], toHex(teeArch, { size: 32 }));
    });

    it("should reject proof with mismatched pubkey", async function () {
      const mockSparsity = await viem.deployContract("MockSparsityVerifier", [true]);
      const adapter = await viem.deployContract("SparsityTEEVerifier", [mockSparsity.address]);

      const [owner, tee, attacker] = await viem.getWalletClients();
      const teeArch = BigInt(1);
      const codeMeasurement = keccak256(toHex("pcr-composite-123"));
      const teePubkey = tee.account.address; // attested pubkey
      const agentWallet = owner.account.address;

      const publicValues = encodeAbiParameters(
        [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }, { type: "address" }],
        [teeArch, codeMeasurement, teePubkey, agentWallet]
      );
      const proofBytes = toHex("zk-proof-data");
      const proof = encodeAbiParameters(
        [{ type: "bytes" }, { type: "bytes" }],
        [publicValues, proofBytes]
      );

      // Claiming a different pubkey than what's attested
      const [success, identifiers] = await adapter.read.verify([proof, attacker.account.address]);
      assert.equal(success, false);
      assert.equal(identifiers.length, 0);
    });

    it("should reject proof when zk verification fails", async function () {
      const mockSparsity = await viem.deployContract("MockSparsityVerifier", [false]);
      const adapter = await viem.deployContract("SparsityTEEVerifier", [mockSparsity.address]);

      const [owner, tee] = await viem.getWalletClients();
      const teeArch = BigInt(1);
      const codeMeasurement = keccak256(toHex("pcr-composite-123"));
      const teePubkey = tee.account.address;
      const agentWallet = owner.account.address;

      const publicValues = encodeAbiParameters(
        [{ type: "uint256" }, { type: "bytes32" }, { type: "address" }, { type: "address" }],
        [teeArch, codeMeasurement, teePubkey, agentWallet]
      );
      const proofBytes = toHex("bad-zk-proof");
      const proof = encodeAbiParameters(
        [{ type: "bytes" }, { type: "bytes" }],
        [publicValues, proofBytes]
      );

      const [success, identifiers] = await adapter.read.verify([proof, teePubkey]);
      assert.equal(success, false);
      assert.equal(identifiers.length, 0);
    });
  });

  // ===== REGISTER AGENT CONVENIENCE =====

  describe("registerAgent convenience", function () {
    it("should register agent in one shot (addKey + linkKey)", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      const codeMeasurement = keccak256(toHex("pcr-composite-456"));
      await verifier.write.setResult([true, [codeMeasurement]]);
      await teeRegistry.write.addVerifier([verifier.address, 1]); // NITRO

      const [owner] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // Mint an agent ID first
      await identityRegistry.write.mint([owner.account.address]);
      const agentId = 1n;

      // One-shot registration
      await teeRegistry.write.registerAgent(
        [toHex("proof"), owner.account.address, toHex("pub-key-bytes"), expiration, verifier.address, agentId]
      );

      // Verify key is registered
      const [valid, identifiers, expiry, storedVerifier, storedPubKeyBytes] =
        await teeRegistry.read.getKey([owner.account.address]);
      assert.equal(valid, true);
      assert.equal(identifiers[0], codeMeasurement);
      assert.equal(storedVerifier.toLowerCase(), verifier.address.toLowerCase());
      assert.equal(storedPubKeyBytes, toHex("pub-key-bytes"));
    });

    it("should reject registerAgent if caller does not own agentId", async function () {
      const identityRegistry = await deployIdentityRegistryProxy();
      const teeRegistry = await deployTEERegistryProxy(identityRegistry.address);

      const verifier = await viem.deployContract("MockTEEVerifier", [true]);
      await teeRegistry.write.addVerifier([verifier.address, 0]);

      const [owner, attacker] = await viem.getWalletClients();
      const expiration = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // Owner mints agent
      await identityRegistry.write.mint([owner.account.address]);
      const agentId = 1n;

      // Attacker tries to register agent on their own key
      await assert.rejects(
        teeRegistry.write.registerAgent(
          [toHex("proof"), attacker.account.address, "0x", expiration, verifier.address, agentId],
          { account: attacker.account }
        ),
        /Not authorized/
      );
    });
  });
});
