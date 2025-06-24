// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/WorkReport.sol";
//deployed address: 0x5FbDB2315678afecb367f032d93F642f64180aa3
contract DeployWorkReport is Script {
    function run() public returns (WorkReport) {
        vm.startBroadcast();
        WorkReport workReport = new WorkReport();
        vm.stopBroadcast();
        return workReport;
    }
}