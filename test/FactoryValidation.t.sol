// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PiePay.sol";
import "../src/PiePayFactory.sol";
import "./mocks/MockUSDC.sol";

contract FactoryValidationTest is Test {
    PiePayFactory public factory;
    MockUSDC public mockToken;
    
    address public projectLead = address(0x1234);
    address public payrollManager = address(0x5678);
    
    function setUp() public {
        // Deploy factory
        factory = new PiePayFactory();
        
        // Deploy mock USDC token
        mockToken = new MockUSDC();
    }
    
    /**
     * @notice Test that PiePay can be deployed through factory
     */
    function testFactoryDeploymentSuccess() public {
        // Prepare project parameters
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Test Project",
            projectDescription: "A test project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: new address[](0),
            paymentToken: address(mockToken)
        });
        
        // Deploy through factory should succeed
        (uint256 projectId, address projectAddress) = factory.createProject(params);
        
        // Verify deployment
        assertEq(projectId, 1);
        assertTrue(projectAddress != address(0));
        
        // Verify factory address is stored correctly
        PiePay piePay = PiePay(projectAddress);
        assertEq(piePay.getFactory(), address(factory));
        
        // Verify project details are set correctly
        assertEq(piePay.projectLead(), projectLead);
        assertEq(piePay.payrollManager(), payrollManager);
        assertEq(address(piePay.paymentToken()), address(mockToken));
    }
    
    /**
     * @notice Test that direct EOA deployment fails
     */
    function testDirectEOADeploymentFails() public {
        // Create an actual EOA account
        address eoaAccount = address(0x999999);
        vm.deal(eoaAccount, 1 ether);
        
        // Prepare parameters
        address[] memory initialContributors = new address[](0);
        
        // Prank as EOA and expect revert
        vm.prank(eoaAccount);
        vm.expectRevert("PiePay can only be deployed by a factory contract");
        
        new PiePay(
            "Test Project",
            "A test project", 
            projectLead,
            payrollManager,
            initialContributors,
            address(mockToken)
        );
    }
    
    /**
     * @notice Test factory validation with different contract
     */
    function testDifferentContractDeployment() public {
        // Deploy a different factory contract
        AlternativeFactory altFactory = new AlternativeFactory();
        
        // Attempt deployment through alternative factory should work
        // (since it's still a contract deploying, not an EOA)
        address piePayAddress = altFactory.deployPiePay(
            address(mockToken),
            projectLead,
            payrollManager
        );
        
        PiePay piePay = PiePay(piePayAddress);
        
        // Verify the factory address is the alternative factory
        assertEq(piePay.getFactory(), address(altFactory));
        assertTrue(piePay.getFactory() != address(factory));
    }
    
    /**
     * @notice Test multiple projects through factory
     */
    function testMultipleProjectsFromFactory() public {
        // Create first project
        PiePayFactory.ProjectParams memory params1 = PiePayFactory.ProjectParams({
            projectName: "Project 1",
            projectDescription: "First project",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: new address[](0),
            paymentToken: address(mockToken)
        });
        
        (uint256 projectId1, address projectAddress1) = factory.createProject(params1);
        
        // Create second project
        PiePayFactory.ProjectParams memory params2 = PiePayFactory.ProjectParams({
            projectName: "Project 2", 
            projectDescription: "Second project",
            projectLead: address(0x2222),
            payrollManager: address(0x3333),
            initialContributors: new address[](0),
            paymentToken: address(mockToken)
        });
        
        (uint256 projectId2, address projectAddress2) = factory.createProject(params2);
        
        // Verify both projects
        assertEq(projectId1, 1);
        assertEq(projectId2, 2);
        assertTrue(projectAddress1 != projectAddress2);
        
        // Both should have same factory
        PiePay piePay1 = PiePay(projectAddress1);
        PiePay piePay2 = PiePay(projectAddress2);
        
        assertEq(piePay1.getFactory(), address(factory));
        assertEq(piePay2.getFactory(), address(factory));
    }
    
    /**
     * @notice Test with initial contributors
     */
    function testFactoryDeploymentWithContributors() public {
        // Prepare initial contributors
        address[] memory initialContributors = new address[](2);
        initialContributors[0] = address(0x1111);
        initialContributors[1] = address(0x2222);
        
        // Prepare project parameters
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Test Project with Contributors",
            projectDescription: "A test project with initial contributors",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: initialContributors,
            paymentToken: address(mockToken)
        });
        
        // Deploy through factory
        (, address projectAddress) = factory.createProject(params);
        
        // Verify deployment
        PiePay piePay = PiePay(projectAddress);
        assertEq(piePay.getFactory(), address(factory));
        
        // Verify initial contributors are whitelisted
        assertTrue(piePay.whitelistedContributors(initialContributors[0]));
        assertTrue(piePay.whitelistedContributors(initialContributors[1]));
    }
    
    /**
     * @notice Test factory validation in existing tests doesn't break
     */
    function testFactoryValidationDoesntBreakExistingFunctionality() public {
        // Deploy project through factory
        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Functional Test Project",
            projectDescription: "Testing that existing functionality still works",
            projectLead: projectLead,
            payrollManager: payrollManager,
            initialContributors: new address[](0),
            paymentToken: address(mockToken)
        });
        
        (, address projectAddress) = factory.createProject(params);
        PiePay piePay = PiePay(projectAddress);
        
        // Test basic functionality still works
        vm.prank(projectLead);
        piePay.whitelistContributor(address(0x9999));
        
        assertTrue(piePay.whitelistedContributors(address(0x9999)));
        
        // Test payroll funding (remember USDC has 6 decimals, not 18)
        uint256 fundAmount = 1000 * 10**6; // 1000 USDC
        mockToken.mint(payrollManager, fundAmount);
        
        vm.startPrank(payrollManager);
        mockToken.approve(address(piePay), fundAmount);
        piePay.fundPayroll(fundAmount);
        vm.stopPrank();
        
        assertEq(piePay.payrollPool(), fundAmount);
    }
}

/**
 * @notice Alternative factory contract for testing
 */
contract AlternativeFactory {
    function deployPiePay(
        address _paymentToken,
        address _projectLead,
        address _payrollManager
    ) external returns (address) {
        address[] memory initialContributors = new address[](0);
        
        PiePay piePay = new PiePay(
            "Alternative Project",
            "Created by alternative factory",
            _projectLead,
            _payrollManager,
            initialContributors,
            _paymentToken
        );
        
        return address(piePay);
    }
}