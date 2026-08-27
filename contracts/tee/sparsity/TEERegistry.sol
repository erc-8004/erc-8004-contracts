// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Verifier interface — each TEE platform implements this.
/// Must revert on invalid attestation; returns the code measurement, public key, and user data.
interface IVerifier {
    function verify(bytes calldata attestation)
        external
        returns (bytes32 codeMeasurement, bytes memory pubKey, bytes memory userData);
}

/// @notice Supported TEE platforms.
enum TEEType {
    TDX,
    NITRO
}

/// @notice A registered TEE identity.
struct TEEEntry {
    address owner;
    TEEType teeType;
    bytes32 codeMeasurement;
    bytes pubKey;
    bytes userData;
    uint64 attestedAt;
    bool active;
}

/// @title TEERegistry — EIP-8004 Reference Implementation
/// @notice On-chain registry of TEE identities verified via platform-specific attestation.
contract TEERegistry is Ownable {
    // ── State ───────────────────────────────────────────────────────────
    // IDs start at 1 so that 0 serves as "not found" sentinel in reverse lookups.
    uint256 public nextId = 1;
    mapping(uint256 => TEEEntry) public entries;
    mapping(bytes32 => uint256[]) internal measurementToIds;
    mapping(TEEType => IVerifier) public verifiers;
    mapping(bytes32 => string) public whitelistedMeasurements;

    // ── Events ──────────────────────────────────────────────────────────
    event Registered(uint256 indexed id, TEEType teeType, bytes32 codeMeasurement, bytes pubKey, bytes userData);
    event Revoked(uint256 indexed id, string reason);
    event VerifierSet(TEEType teeType, address verifier);
    event MeasurementWhitelisted(bytes32 indexed measurement, string url);
    event MeasurementRemoved(bytes32 indexed measurement);

    // ── Errors ──────────────────────────────────────────────────────────
    error VerifierNotConfigured(TEEType teeType);
    error MeasurementNotWhitelisted(bytes32 measurement);
    error NotEntryOwnerOrAdmin(uint256 id);
    error EntryNotActive(uint256 id);

    constructor() Ownable(msg.sender) {}

    // ── Admin ───────────────────────────────────────────────────────────
    function setVerifier(TEEType teeType, address verifier) external onlyOwner {
        verifiers[teeType] = IVerifier(verifier);
        emit VerifierSet(teeType, verifier);
    }

    function whitelistMeasurement(bytes32 measurement, string calldata url) external onlyOwner {
        whitelistedMeasurements[measurement] = url;
        emit MeasurementWhitelisted(measurement, url);
    }

    function removeWhitelistedMeasurement(bytes32 measurement) external onlyOwner {
        delete whitelistedMeasurements[measurement];
        emit MeasurementRemoved(measurement);
    }

    // ── Registration ────────────────────────────────────────────────────
    function register(TEEType teeType, bytes calldata attestation) external returns (uint256 id) {
        IVerifier v = verifiers[teeType];
        if (address(v) == address(0)) revert VerifierNotConfigured(teeType);

        (bytes32 codeMeasurement, bytes memory pubKey, bytes memory userData) = v.verify(attestation);

        if (bytes(whitelistedMeasurements[codeMeasurement]).length == 0) {
            revert MeasurementNotWhitelisted(codeMeasurement);
        }

        id = nextId++;
        entries[id] = TEEEntry({
            owner: msg.sender,
            teeType: teeType,
            codeMeasurement: codeMeasurement,
            pubKey: pubKey,
            userData: userData,
            attestedAt: uint64(block.timestamp),
            active: true
        });
        measurementToIds[codeMeasurement].push(id);

        emit Registered(id, teeType, codeMeasurement, pubKey, userData);
    }

    // ── Revocation ──────────────────────────────────────────────────────
    function revoke(uint256 id, string calldata reason) external {
        TEEEntry storage entry = entries[id];
        if (!entry.active) revert EntryNotActive(id);
        if (msg.sender != entry.owner && msg.sender != owner()) revert NotEntryOwnerOrAdmin(id);

        entry.active = false;
        emit Revoked(id, reason);
    }

    // ── Views ───────────────────────────────────────────────────────────
    function getEntry(uint256 id) external view returns (TEEEntry memory) {
        return entries[id];
    }

    function isActive(uint256 id) external view returns (bool) {
        return entries[id].active;
    }

    function getByMeasurement(bytes32 measurement) external view returns (uint256[] memory ids) {
        ids = measurementToIds[measurement];
    }
}
