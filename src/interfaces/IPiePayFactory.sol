// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPiePayFactory
 * @notice Interface for the PiePayFactory to allow PiePay contracts to query their project ID
 */
interface IPiePayFactory {
    /**
     * @notice Get the project ID for a given PiePay contract address
     * @param projectAddress The address of the PiePay contract
     * @return The project ID, or 0 if not found
     */
    function getProjectId(address projectAddress) external view returns (uint256);
    
    /**
     * @notice Check if an address is a valid PiePay project created by this factory
     * @param projectAddress The address to check
     * @return Whether the address is a valid project
     */
    function isValidProject(address projectAddress) external view returns (bool);
}