// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockUSDC} from "../src/mock/MockUSDC.sol";
import {PiePay} from "../src/PiePay.sol";  // Assuming your PiePay contract is in src/PiePay.sol

contract DeployLocal is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));

        // Define test accounts
        address deployer = msg.sender;  // 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        address account2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address account3 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

        // Amount: 100K MockUSDC (considering 6 decimals)
        uint256 amount = 100_000 * (10 ** usdc.decimals());

        // Transfer 100K to each non-deployer test account
        usdc.transfer(account2, amount);
        usdc.transfer(account3, amount);

        // Prepare empty contributors array
        address[] memory initialContributors = new address[](0);

        // Deploy PiePay with test values
        // You can customize these hardcoded args as needed
        PiePay piepay = new PiePay(
            "Test Project",                // _projectName
            "Local test description",      // _projectDescription
            msg.sender,                    // _projectLead (deployer)
            msg.sender,                    // _payrollManager (deployer)
            initialContributors,           // _initialContributors (empty)
            address(usdc)                  // _paymentToken (MockUSDC)
        );
        console.log("PiePay deployed at:", address(piepay));

        vm.stopBroadcast();
    }
}