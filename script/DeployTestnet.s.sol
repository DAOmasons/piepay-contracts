// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PiePay.sol";
import "../test/mocks/MockUSDC.sol";

contract DeployTestnet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDC first
        MockUSDC mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));

        // Set up initial contributors (you can modify these addresses)
        address[] memory initialContributors = new address[](2);
        initialContributors[0] = deployer;
        initialContributors[1] = 0x742d35Cc6634C0532925a3b8D0C70D4f8f6FFA4C; // Example address

        // Deploy PiePay contract
        PiePay piePay = new PiePay(
            "Test PiePay Project",
            "A test project for PiePay profit sharing system",
            deployer,           // projectLead
            deployer,           // payrollManager  
            initialContributors,
            address(mockUSDC)   // paymentToken
        );

        console.log("PiePay deployed at:", address(piePay));
        console.log("Project Lead:", piePay.projectLead());
        console.log("Payroll Manager:", piePay.payrollManager());
        console.log("Payment Token:", piePay.paymentToken());
        console.log("Contributor Count:", piePay.getContributorCount());

        // Fund the deployer with some mock USDC for testing
        mockUSDC.mint(deployer, 10000 * 10**6); // 10,000 USDC
        console.log("Minted 10,000 USDC to deployer");

        // Approve PiePay to spend USDC (for payroll funding)
        mockUSDC.approve(address(piePay), type(uint256).max);
        console.log("Approved PiePay to spend USDC");

        vm.stopBroadcast();

        // Save deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "# Testnet Deployment Info\n",
            "MockUSDC: ", vm.toString(address(mockUSDC)), "\n",
            "PiePay: ", vm.toString(address(piePay)), "\n",
            "Deployer: ", vm.toString(deployer), "\n"
        ));
        
        vm.writeFile("./deployment.txt", deploymentInfo);
        console.log("Deployment info saved to deployment.txt");
    }
}