// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/WorkReport.sol";

contract WorkReportTest is Test {
    // --- Test State Variables ---
    WorkReport public workReport;
    address public owner;
    address public projectLead = makeAddr("projectLead");
    address public contributor = makeAddr("contributor");
    address public outsider = makeAddr("outsider");

    // --- Setup Function ---
    function setUp() public {
        workReport = new WorkReport();
        owner = address(this);
    }

    // ... (Previous tests remain the same) ...
    function test_OwnerAsLeadCanAddContributor() public {
        workReport.addContributor(contributor);
        assertTrue(workReport.isContributor(contributor));
    }

    function test_OwnerCanAddProjectLead() public {
        workReport.addProjectLead(projectLead);
        assertTrue(workReport.isProjectLead(projectLead));
    }

    function test_Revert_NonOwnerCannotAddProjectLead() public {
        vm.prank(outsider);
        vm.expectRevert("Not the owner");
        workReport.addProjectLead(projectLead);
    }

    function test_ProjectLeadCanAddContributor() public {
        workReport.addProjectLead(projectLead);
        vm.prank(projectLead);
        workReport.addContributor(contributor);
        assertTrue(workReport.isContributor(contributor));
    }

    function test_Revert_OutsiderCannotAddContributor() public {
        vm.prank(outsider);
        vm.expectRevert("Not a project lead");
        workReport.addContributor(contributor);
    }
    
    // MODIFIED: This test now also checks the default approval status.
    function test_ContributorCanSubmitReport() public {
        workReport.addContributor(contributor);
        vm.prank(contributor);
        workReport.submitReport("Updated documentation", 250);
        (address reporter,,uint256 dollarValue, bool isApproved) = workReport.reports(0);
        assertEq(reporter, contributor);
        assertEq(dollarValue, 250);
        // NEW ASSERTION: Verify the report is not approved by default.
        assertFalse(isApproved, "Report should not be approved by default");
    }

    function test_ProjectLeadCanSetReportApproval() public {
        // Arrange: A report is submitted.
        workReport.addContributor(contributor);
        workReport.addProjectLead(projectLead);

        vm.prank(contributor);
        workReport.submitReport("Fixed critical bug", 1000);

        // Act: The project lead approves the report.
        vm.prank(projectLead);
        workReport.setReportApproval(0, true);

        // Assert: The report is now approved.
        (,,, bool isApproved) = workReport.reports(0);
        assertTrue(isApproved, "Report should be approved");
    }

    // NEW TEST: Verify a non-lead cannot approve a report.
    function test_Revert_NonLeadCannotSetApproval() public {
        // Arrange: A report is submitted.
        workReport.addContributor(contributor);
        vm.prank(contributor);
        workReport.submitReport("Wrote a test", 100);

        // Act & Assert: An outsider's attempt to approve should fail.
        vm.prank(outsider);
        vm.expectRevert("Not a project lead");
        workReport.setReportApproval(0, true);
    }
}