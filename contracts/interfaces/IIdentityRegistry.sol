// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IIdentityRegistry
 * @notice Interface for the IdentityRegistry contract
 * @dev This interface is used by ReputationRegistry and ValidationRegistry contracts
 * to interact with the IdentityRegistry for ownership and approval checks
 */
interface IIdentityRegistry {
    /**
     * @notice Returns the owner of a given agent NFT
     * @param tokenId The ID of the agent token
     * @return The address of the owner
     */
    function ownerOf(uint256 tokenId) external view returns (address);

    /**
     * @notice Checks if an operator is approved to manage all of an owner's tokens
     * @param owner The owner address
     * @param operator The operator address to check
     * @return True if the operator is approved for all tokens
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @notice Returns the approved address for a single token
     * @param tokenId The ID of the agent token
     * @return The address approved for this token
     */
    function getApproved(uint256 tokenId) external view returns (address);
}
