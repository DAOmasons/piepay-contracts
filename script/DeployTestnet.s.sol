// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PiePayFactory.sol";
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

        // Deploy PiePayFactory
        PiePayFactory factory = new PiePayFactory();
        console.log("PiePayFactory deployed at:", address(factory));

        // Fund the deployer with some mock USDC for testing
        mockUSDC.mint(deployer, 10000 * 10**6); // 10,000 USDC
        console.log("Minted 10,000 USDC to deployer");

        vm.stopBroadcast();

        // Save deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "# Testnet Deployment Info\n",
            "MockUSDC: ", vm.toString(address(mockUSDC)), "\n",
            "PiePayFactory: ", vm.toString(address(factory)), "\n",
            "Deployer: ", vm.toString(deployer), "\n"
        ));
        
        vm.writeFile("./deployment.txt", deploymentInfo);
        console.log("Deployment info saved to deployment.txt");
    }
}