// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PiePayFactory.sol";
import "../src/mock/MockUSDC.sol";

contract DeployFactoryArbitrumSepolia is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MockUSDC for testing (if needed)
        MockUSDC mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));
        
        // Deploy PiePayFactory
        PiePayFactory factory = new PiePayFactory();
        console.log("PiePayFactory deployed at:", address(factory));
        
        // Create a sample project to test
        // Note: project lead and payroll manager are auto-whitelisted, so don't include them in initialContributors
        address[] memory initialContributors = new address[](0);

        PiePayFactory.ProjectParams memory params = PiePayFactory.ProjectParams({
            projectName: "Demo PiePay Project",
            projectDescription: "A demonstration project for PiePay profit sharing system",
            projectLead: deployer,
            payrollManager: deployer,
            initialContributors: initialContributors,
            paymentToken: address(mockUSDC)
        });
        
        (uint256 projectId, address projectAddress) = factory.createProject(params);
        
        console.log("Demo project created:");
        console.log("  Project ID:", projectId);
        console.log("  Project Address:", projectAddress);
        console.log("  Project Lead:", deployer);
        console.log("  Payment Token:", address(mockUSDC));
        
        vm.stopBroadcast();
        
        // Output deployment information
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Network: Arbitrum Sepolia");
        console.log("Factory Address:", address(factory));
        console.log("MockUSDC Address:", address(mockUSDC));
        console.log("Demo Project ID:", projectId);
        console.log("Demo Project Address:", projectAddress);
        console.log("\nTo interact with the factory:");
        console.log("1. Call createProject() to deploy new PiePay instances");
        console.log("2. Use project ID", projectId, "to track events for the demo project");
        console.log("3. Each PiePay instance will emit events with their contract address");
    }
}