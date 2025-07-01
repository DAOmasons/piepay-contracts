// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PiePay.sol";

contract DeployPiePay is Script {
    function run() public returns (PiePay) {
        vm.startBroadcast();
        
        // You'll need to provide constructor parameters
        address[] memory initialContributors = new address[](0);
        
        PiePay piePay = new PiePay(
            "My Project",
            "Project Description", 
            msg.sender, // projectLead
            msg.sender, // payrollManager
            initialContributors,
            address(0) // tokenAddress - you'd use real token address
        );
        
        vm.stopBroadcast();
        return piePay;
    }
}