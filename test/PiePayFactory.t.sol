// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PiePayFactory.sol";
import "../src/PiePay.sol";
import "../src/mock/MockUSDC.sol";

contract PiePayFactoryTest is Test {
    PiePayFactory public factory;
    MockUSDC public mockUSDC;
    
    address public deployer = address(0x1);
    address public projectLead = address(0x2);
    address public payrollManager = address(0x3);
    address public contributor1 = address(0x4);
    address public contributor2 = address(0x5);
    
    function setUp() public {
        vm.startPrank(deployer);
        
        // Deploy mock USDC
        mockUSDC = new MockUSDC();
        
        // Deploy factory
        factory = new PiePayFactory();
        
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(factory.projectCounter(), 1);
        // getTotalProjects() removed to reduce contract size
        // assertEq(factory.getTotalProjects(), 0);
    }
    
    function testCreateProject() public {
        address[] memory initialContributors = new address[](2);
        initialContributors[0] = contributor1;
        initialContributors[1] = contributor2;
        
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Test Project",
            projectDescription: "A test project for PiePay",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.prank(deployer);
        (uint256 projectId, address projectAddress) = factory.createProject(params);
        
        // Check project ID and address
        assertEq(projectId, 1);
        assertNotEq(projectAddress, address(0));
        
        // Check factory state
        assertEq(factory.projectCounter(), 2);
        // getTotalProjects() and getProjectInfo() removed to reduce contract size
        // assertEq(factory.getTotalProjects(), 1);
        assertEq(factory.getProject(projectId), projectAddress);
        assertEq(factory.getProjectId(projectAddress), projectId);

        // Project info functionality removed to reduce contract size
        // Check data from events instead
        
        // Check that PiePay contract was properly initialized
        PiePay piePayContract = PiePay(projectAddress);
        assertEq(piePayContract.projectLead(), projectLead);
        assertEq(piePayContract.payrollManager(), payrollManager);
        assertEq(address(piePayContract.paymentToken()), address(mockUSDC));
        
        // Check initial contributors were whitelisted
        assertTrue(piePayContract.whitelistedContributors(contributor1));
        assertTrue(piePayContract.whitelistedContributors(contributor2));
    }
    
    function testCreateProjectEvent() public {
        address[] memory initialContributors = new address[](0);
        
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Test Project",
            projectDescription: "A test project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        // Check that an event is emitted (without checking the exact address)
        vm.expectEmit(true, false, true, true);
        emit PiePayFactory.ProjectCreated(
            1,
            address(0), // Don't check the exact address
            "Test Project",
            "A test project",
            projectLead,
            payrollManager,
            address(mockUSDC),
            deployer
        );
        
        vm.prank(deployer);
        (uint256 projectId, address projectAddress) = factory.createProject(params);
        
        // Verify the project was created correctly
        assertEq(projectId, 1);
        assertNotEq(projectAddress, address(0));
    }
    
    function testMultipleProjects() public {
        address[] memory initialContributors = new address[](0);
        
        // Create first project
        PiePayFactory.ProjectParams memory params1 = PiePayFactory.ProjectParams({
            projectName: "Project 1",
            projectDescription: "First project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.prank(deployer);
        (uint256 projectId1, address projectAddress1) = factory.createProject(params1);
        
        // Create second project
        PiePayFactory.ProjectParams memory params2 = PiePayFactory.ProjectParams({
            projectName: "Project 2",
            projectDescription: "Second project",
            projectLead: address(0x6),
            payrollManager: address(0x7),
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.prank(address(0x8));
        (uint256 projectId2, address projectAddress2) = factory.createProject(params2);
        
        // Check both projects exist
        assertEq(projectId1, 1);
        assertEq(projectId2, 2);
        assertNotEq(projectAddress1, projectAddress2);
        // getTotalProjects() removed to reduce contract size
        // assertEq(factory.getTotalProjects(), 2);
        
        // Check projects by creator
        uint256[] memory deployerProjects = factory.getProjectsByCreator(deployer);
        assertEq(deployerProjects.length, 1);
        assertEq(deployerProjects[0], projectId1);
        
        uint256[] memory otherCreatorProjects = factory.getProjectsByCreator(address(0x8));
        assertEq(otherCreatorProjects.length, 1);
        assertEq(otherCreatorProjects[0], projectId2);
    }
    
    // getProjectsBatch() removed to reduce contract size - use indexer instead
    // function testGetProjectsBatch() public { ... }

    // updateProjectMetadata() and getProjectInfo() removed to reduce contract size
    // function testUpdateProjectMetadata() public { ... }
    
    function test_RevertWhen_EmptyProjectName() public {
        address[] memory initialContributors = new address[](0);
        
        // Test empty project name
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "",
            projectDescription: "Test project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.expectRevert("Project name required");
        vm.prank(deployer);
        factory.createProject(params);
    }
    
    // updateProjectMetadata() removed to reduce contract size
    // function test_RevertWhen_UnauthorizedMetadataUpdate() public { ... }
    
    function testIsValidProject() public {
        address[] memory initialContributors = new address[](0);
        
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Test Project",
            projectDescription: "Test project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.prank(deployer);
        (, address projectAddress) = factory.createProject(params);
        
        assertTrue(factory.isValidProject(projectAddress));
        assertFalse(factory.isValidProject(address(0x9999)));
    }
}