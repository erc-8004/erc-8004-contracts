# ERC-8004 Security Audit Report

**Date**: February 13, 2026
**Auditor**: [@saiboyizhan](https://github.com/saiboyizhan)
**Scope**: All three registry contracts in `contracts/`
**Commit**: Audited against `master` branch

---

## Summary

| Severity | Count | Fixed | Description |
|----------|-------|-------|-------------|
| High | 1 | Yes | Validation response values can be manipulated downward |
| Medium | 3 | — | Design-level concerns requiring discussion |
| Low | 3 | — | Minor issues with limited impact |
| Informational | 2 | Yes | Test correctness issues |

---

## High Severity

### H-1: Rogue Validators Can Decrease Response Values (Fixes #28)

**Contract**: `ValidationRegistryUpgradeable.sol`
**Function**: `validationResponse()` (line 115-133)

**Description**: The `validationResponse()` function allows validators to call it multiple times for the same `requestHash`. While this is intentional (supporting progressive validation states like "soft finality" → "hard finality"), there is no enforcement preventing a validator from **decreasing** the response value.

**Attack Scenario**:
```
1. Validator submits response = 100 (COMPLETED/PASSED)
2. Downstream indexers and UIs treat this as finalized
3. Validator submits response = 0 (reverts to FAILED)
4. State oscillates, breaking downstream reliability
```

**Impact**: Event listeners and indexers that treat `response == 100` as a terminal `COMPLETED` state lose reliability. This creates data inconsistency and potential trust manipulation.

**Fix Applied**: Added monotonic increase enforcement:
```solidity
require(response >= s.response, "response cannot decrease");
```

This ensures response values can only stay the same or increase, which aligns with the progressive validation use case (soft finality → hard finality) while preventing downgrade attacks.

**Tests Added**:
- `Should reject decreasing validation response values` — verifies decrease from 80→50 and 80→0 both revert
- Verifies equal value (80→80) and increase (80→100) still work

---

## Medium Severity

### M-1: Unbounded Array Returns in View Functions

**Contracts**: `ValidationRegistryUpgradeable.sol`
**Functions**: `getAgentValidations()`, `getValidatorRequests()`

**Description**: These functions return the entire array of request hashes without pagination. For agents or validators with many validations, this could exceed block gas limits when called from other contracts, or cause timeouts for off-chain callers.

**Recommendation**: Add paginated versions:
```solidity
function getAgentValidations(uint256 agentId, uint256 offset, uint256 limit)
    external view returns (bytes32[] memory)
```

### M-2: Inconsistent IIdentityRegistry Interface Definitions

**Contracts**: `ValidationRegistryUpgradeable.sol` vs `ReputationRegistryUpgradeable.sol`

**Description**: Each contract defines its own `IIdentityRegistry` interface with different function signatures:

| Contract | Interface Methods |
|----------|------------------|
| ValidationRegistry | `ownerOf()`, `getApproved()`, `isApprovedForAll()` |
| ReputationRegistry | `isAuthorizedOrOwner()` |

**Impact**: If the IdentityRegistry contract is upgraded to change authorization logic, one registry might break while the other continues working. This also increases maintenance burden.

**Recommendation**: Extract a shared `IIdentityRegistry` interface into a separate file and import it in both contracts.

### M-3: No Mechanism to Cancel Validation Requests

**Contract**: `ValidationRegistryUpgradeable.sol`

**Description**: Once a `validationRequest()` is created, there is no way for the agent owner to cancel it. If a validator becomes unresponsive or malicious, the request remains in a permanent `PENDING` state, polluting the agent's validation history.

**Recommendation**: Add a `cancelValidationRequest()` function callable by the agent owner after a timeout period.

---

## Low Severity

### L-1: No Storage Gap for Plain State Variables

**Contracts**: `ValidationRegistryUpgradeable.sol`, `ReputationRegistryUpgradeable.sol`

**Description**: Both contracts store `_identityRegistry` as a plain state variable (outside ERC-7201 namespaced storage). While the main storage structs use ERC-7201 (mitigating most upgrade collision risks), adding new plain state variables in future upgrades could cause storage slot conflicts.

**Note**: The comment says `_identityRegistry` is "stored at slot 0 (matches MinimalUUPS)", indicating this is intentional for the upgrade pattern. However, future developers should be aware not to add new plain state variables.

### L-2: No Limit on Response Append Count

**Contract**: `ReputationRegistryUpgradeable.sol`
**Function**: `appendResponse()`

**Description**: There is no limit on how many responses can be appended to a single feedback entry. A malicious responder could spam unlimited responses, increasing storage costs for the contract.

**Impact**: Low — storage costs are borne by the caller, and responses are tracked per-responder. However, the `_responders` array grows unboundedly.

### L-3: getSummary Gas Cost Scales Quadratically

**Contract**: `ValidationRegistryUpgradeable.sol`
**Function**: `getSummary()`

**Description**: The function iterates over all validations for an agent, then for each validation iterates over the `validatorAddresses` filter array. This O(n*m) complexity could become expensive for agents with many validations and large filter arrays.

**Impact**: Low — this is a `view` function, so it doesn't consume on-chain gas. But it could timeout for off-chain callers with large datasets.

---

## Informational

### I-1: Test Uses Wrong Parameter Type for getSummary Tag Filter (Fixed)

**File**: `test/core.ts` (line ~1799-1804)

**Description**: The test "Should get validation summary and track validations" passed a bytes32 hex string (`"0x000...000"`) to the `string calldata tag` parameter. Since the function expects a string, this 66-character hex string doesn't match the empty-string wildcard check and doesn't match any stored tags, causing the test to assert `count = 0`.

The test acknowledged this with a comment: *"Contract has bug where getSummary takes bytes32 but stores string tags"* — but this was actually a **test bug**, not a contract bug. The contract's `getSummary` function correctly accepts `string calldata tag` and the tag filtering logic works properly.

**Fix Applied**: Updated the test to use proper string parameters (`tag` for exact match, `""` for wildcard) and correct assertions (`count = 2`, `avg = 90`).

### I-2: Positive Findings

The following security practices were noted positively:
- **ERC-7201 Namespaced Storage**: All three contracts use the namespaced storage pattern, reducing upgrade collision risks
- **UUPS Upgrade Pattern**: Properly implemented with `_disableInitializers()` in constructors
- **Self-Feedback Prevention**: ReputationRegistry correctly prevents agent owners from giving feedback to their own agents
- **EIP-712 + ERC-1271 Wallet Verification**: IdentityRegistry supports both EOA and smart contract wallet verification for `setAgentWallet()`
- **Transfer Clears Wallet**: `agentWallet` metadata is properly cleared on NFT transfer, preventing stale wallet associations

---

## Test Coverage Summary

This audit adds **4 new test cases** (61 → 65 total):

| Test | Area | Validates |
|------|------|-----------|
| `Should reject decreasing validation response values` | H-1 fix | Monotonic response enforcement |
| `Should filter getSummary by string tag correctly` | I-1 fix | Tag filtering with string types |
| `Should filter getSummary by validator addresses` | M-1 related | Validator address filtering |
| `Should exclude pending validations from getSummary` | Correctness | hasResponse flag behavior |

---

## Files Changed

| File | Changes |
|------|---------|
| `contracts/ValidationRegistryUpgradeable.sol` | Added `require(response >= s.response)` in `validationResponse()` |
| `test/core.ts` | Fixed getSummary test parameters; added 4 security test cases |

---

*This audit was performed as a community contribution. It is not a substitute for a formal security audit by a professional auditing firm.*
