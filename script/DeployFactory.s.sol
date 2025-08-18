// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PiePayFactory.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy PiePayFactory
        PiePayFactory factory = new PiePayFactory();
        
        console.log("PiePayFactory deployed at:", address(factory));
        console.log("Initial project counter:", factory.projectCounter());
        
        vm.stopBroadcast();
    }
}