// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./PiePay.sol";

/**
 * @title PiePayFactory
 * @notice Factory contract for deploying PiePay project instances
 * @dev Creates new PiePay contracts and tracks them with unique project IDs
 */
contract PiePayFactory {
    
    // ============ STATE VARIABLES ============
    
    /// @notice Counter for generating unique project IDs
    uint256 public projectCounter;
    
    /// @notice Mapping from project ID to PiePay contract address
    mapping(uint256 => address) public projects;
    
    /// @notice Mapping from PiePay contract address to project ID
    mapping(address => uint256) public projectIds;
    
    /// @notice Mapping from creator address to their created project IDs
    mapping(address => uint256[]) public projectsByCreator;
    
    // ============ EVENTS ============
    
    /**
     * @notice Emitted when a new PiePay project is created
     * @param projectId The unique ID assigned to the project
     * @param projectAddress The deployed contract address
     * @param projectName The name of the project
     * @param projectDescription Brief description of the project
     * @param projectLead Address of the project lead
     * @param payrollManager Address of the payroll manager
     * @param paymentToken Token used for payments
     * @param creator Address that created the project
     */
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed projectAddress,
        string projectName,
        string projectDescription,
        address indexed projectLead,
        address payrollManager,
        address paymentToken,
        address creator
    );

    // ============ STRUCTS ============
    
    /**
     * @notice Struct containing project creation parameters
     */
    struct ProjectParams {
        string projectName;
        string projectDescription;
        address projectLead;
        address payrollManager;
        address[] initialContributors;
        address paymentToken;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor() {
        // Start project IDs from 1 (0 reserved for "no project")
        projectCounter = 1;
    }
    
    // ============ EXTERNAL FUNCTIONS ============
    
    /**
     * @notice Create a new PiePay project instance
     * @param params The project creation parameters
     * @return projectId The unique ID assigned to the new project
     * @return projectAddress The address of the deployed PiePay contract
     */
    function createProject(ProjectParams calldata params) 
        external 
        returns (uint256 projectId, address projectAddress) 
    {
        require(bytes(params.projectName).length > 0, "Project name required");
        require(params.projectLead != address(0), "Invalid project lead");
        require(params.payrollManager != address(0), "Invalid payroll manager");
        require(params.paymentToken != address(0), "Invalid payment token");
        
        // Generate new project ID
        projectId = projectCounter++;
        
        // Deploy new PiePay contract
        PiePay newProject = new PiePay(
            params.projectName,
            params.projectDescription,
            params.projectLead,
            params.payrollManager,
            params.initialContributors,
            params.paymentToken
        );
        
        projectAddress = address(newProject);
        
        // Store project mappings
        projects[projectId] = projectAddress;
        projectIds[projectAddress] = projectId;
        projectsByCreator[msg.sender].push(projectId);

        emit ProjectCreated(
            projectId,
            projectAddress,
            params.projectName,
            params.projectDescription,
            params.projectLead,
            params.payrollManager,
            params.paymentToken,
            msg.sender
        );
        
        return (projectId, projectAddress);
    }
    
    /**
     * @notice Get project address by ID
     * @param projectId The project ID to look up
     * @return The contract address of the project
     */
    function getProject(uint256 projectId) external view returns (address) {
        require(projectId > 0 && projectId < projectCounter, "Invalid project ID");
        return projects[projectId];
    }
    
    /**
     * @notice Get project ID by contract address
     * @param projectAddress The project contract address
     * @return The project ID
     */
    function getProjectId(address projectAddress) external view returns (uint256) {
        uint256 projectId = projectIds[projectAddress];
        require(projectId != 0, "Project not found");
        return projectId;
    }
    
    /**
     * @notice Get all project IDs created by a specific address
     * @param creator The creator address
     * @return Array of project IDs
     */
    function getProjectsByCreator(address creator) external view returns (uint256[] memory) {
        return projectsByCreator[creator];
    }
    
    /**
     * @notice Check if an address is a valid PiePay project created by this factory
     * @param projectAddress The address to check
     * @return Whether the address is a valid project
     */
    function isValidProject(address projectAddress) external view returns (bool) {
        return projectIds[projectAddress] != 0;
    }
    
    /**
     * @notice Get the latest project ID
     * @return The most recently created project ID
     */
    function getLatestProjectId() external view returns (uint256) {
        require(projectCounter > 1, "No projects created yet");
        return projectCounter - 1;
    }
}