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
        assertEq(factory.getTotalProjects(), 0);
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
        assertEq(factory.getTotalProjects(), 1);
        assertEq(factory.getProject(projectId), projectAddress);
        assertEq(factory.getProjectId(projectAddress), projectId);
        
        // Check project info
        PiePayFactory.ProjectInfo memory info = factory.getProjectInfo(projectId);
        assertEq(info.projectId, projectId);
        assertEq(info.projectAddress, projectAddress);
        assertEq(info.projectName, "Test Project");
        assertEq(info.projectDescription, "A test project for PiePay");
        assertEq(info.projectLead, projectLead);
        assertEq(info.payrollManager, payrollManager);
        assertEq(info.paymentToken, address(mockUSDC));
        assertEq(info.creator, deployer);
        assertEq(info.createdAt, block.timestamp);
        
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
        assertEq(factory.getTotalProjects(), 2);
        
        // Check projects by creator
        uint256[] memory deployerProjects = factory.getProjectsByCreator(deployer);
        assertEq(deployerProjects.length, 1);
        assertEq(deployerProjects[0], projectId1);
        
        uint256[] memory otherCreatorProjects = factory.getProjectsByCreator(address(0x8));
        assertEq(otherCreatorProjects.length, 1);
        assertEq(otherCreatorProjects[0], projectId2);
    }
    
    function testGetProjectsBatch() public {
        address[] memory initialContributors = new address[](0);
        
        // Create 3 projects
        for (uint i = 0; i < 3; i++) {
            PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
                projectName: string(abi.encodePacked("Project ", vm.toString(i + 1))),
                projectDescription: "Test project",
                projectLead: projectLead,
                payrollManager: payrollManager,
                initialContributors: initialContributors,
                paymentToken: address(mockUSDC)
            });
            
            vm.prank(deployer);
            factory.createProject(params);
        }
        
        // Test batch retrieval
        (address[] memory batch1, bool hasMore1) = factory.getProjectsBatch(0, 2);
        assertEq(batch1.length, 2);
        assertTrue(hasMore1);
        
        (address[] memory batch2, bool hasMore2) = factory.getProjectsBatch(2, 2);
        assertEq(batch2.length, 1);
        assertFalse(hasMore2);
    }
    
    function testUpdateProjectMetadata() public {
        address[] memory initialContributors = new address[](0);
        
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Original Name",
            projectDescription: "Original Description",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        vm.prank(deployer);
        (uint256 projectId, ) = factory.createProject(params);
        
        // Update metadata as project lead
        vm.prank(projectLead);
        factory.updateProjectMetadata(projectId, "Updated Name", "Updated Description");
        
        // Check updated info
        PiePayFactory.ProjectInfo memory info = factory.getProjectInfo(projectId);
        assertEq(info.projectName, "Updated Name");
        assertEq(info.projectDescription, "Updated Description");
    }
    
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
    
    function test_RevertWhen_UnauthorizedMetadataUpdate() public {
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
        (uint256 projectId, ) = factory.createProject(params);
        
        // Try to update as non-project-lead
        vm.expectRevert("Only project lead can update metadata");
        vm.prank(deployer);
        factory.updateProjectMetadata(projectId, "Updated Name", "Updated Description");
    }
    
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