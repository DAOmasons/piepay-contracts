// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PiePay.sol";
import "./mocks/MockUSDC.sol";

contract PiePayTest is Test {
    PiePay public piePay;
    MockUSDC public usdc;
    
    address public owner;
    address public projectLead;
    address public payrollManager;
    address public contributor1;
    address public contributor2;

    event PayrollFunded(uint256 amount);
    
    PiePay.ValuationRubric public testRubric;
    
    function setUp() public {
        owner = address(this);
        projectLead = makeAddr("projectLead");
        payrollManager = makeAddr("payrollManager");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");

        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Set up valuation rubric - stored as cents per minute (100e18 = $1)
        testRubric = PiePay.ValuationRubric({
            factor1Rate: 4167e16,   // $~25/hour - Junior/Learning tasks
            factor2Rate: 6667e16,   // $~40/hour - Standard development
            factor3Rate: 100e16,   // $60/hour - Senior/Complex work
            factor4Rate: 14167e16,   // $85/hour - Expert/Leadership
            factor5Rate: 200e16   // $120/hour - Critical/Specialized
        });
        
        // Create initial contributors array
        address[] memory initialContributors = new address[](2);
        initialContributors[0] = contributor1;
        initialContributors[1] = contributor2;
        
        // Deploy contract
        piePay = new PiePay(
            "Test Project",
            "A test project for PiePay",
            projectLead,
            payrollManager,
            initialContributors,
            testRubric,
            address(usdc)
            //0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE //SplitMain address
        );

        // Give payroll manager some USDC
        usdc.mint(payrollManager, 10000 * 10**6); // 10,000 USDC
    }
    
    function testInitialSetup() public {
        assertEq(piePay.projectName(), "Test Project");
        assertEq(piePay.projectDescription(), "A test project for PiePay");
        assertEq(piePay.projectLead(), projectLead);
        assertEq(piePay.payrollManager(), payrollManager);
        assertTrue(piePay.whitelistedContributors(contributor1));
        assertTrue(piePay.whitelistedContributors(contributor2));
        assertEq(piePay.getContributorCount(), 2);
    }
    
    function testSubmitContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(480, 3, "Implemented new feature");
        
        (uint256 minutesWorked, uint8 valuationFactor, string memory description, 
         PiePay.ContributionStatus status, uint256 timestamp, 
         address contributor, string memory leadComment, uint256 pUnitsEarned) = 
         piePay.contributions(1);
        
        assertEq(minutesWorked, 480);
        assertEq(valuationFactor, 3);
        assertEq(description, "Implemented new feature");
        assertEq(uint(status), uint(PiePay.ContributionStatus.Pending));
        assertEq(contributor, contributor1);
        assertEq(pUnitsEarned, 0); // Not approved yet
    }

    function testReviewContributionAccepted() public {

        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(60, 3, "Implemented new feature"); //60 minutes @ $60/hr = $60 = 60 P Units
        
        // Reject contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        

                //Pull valuation factors from the contract
       (, , uint256 factor3Rate, ,) = 
        piePay.valuationRubric();
        uint256 expectedUnitsEarned = 60 * factor3Rate;



        // Check contribution status
        (, , , PiePay.ContributionStatus status, , , string memory leadComment, uint256 pUnitsEarned) = 
         piePay.contributions(1);
        
        assertEq(uint(status), uint(PiePay.ContributionStatus.Approved));
        assertEq(leadComment, "Approved");
        assertEq(pUnitsEarned, expectedUnitsEarned); // 60 minutes * factor3 rate
        
        // Check P-Units balance (should be 0)
        (uint256 pUnits, , ) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, expectedUnitsEarned);
    }


     function testReviewContributionRejected() public {
        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(8, 3, "Implemented new feature");
        
        // Reject contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, false, "Needs more work");
        
        // Check contribution status
        (, , , PiePay.ContributionStatus status, , , string memory leadComment, uint256 pUnitsEarned) = 
         piePay.contributions(1);
        
        assertEq(uint(status), uint(PiePay.ContributionStatus.Rejected));
        assertEq(leadComment, "Needs more work");
        assertEq(pUnitsEarned, 0);
        
        // Check P-Units balance (should be 0)
        (uint256 pUnits, , ) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, 0);
    }

    function testSubmitManyContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(480, 3, "Implemented new feature (8 hours)");
        vm.prank(contributor1);
        piePay.submitContribution(120, 5, "Fixed that tricky bug (2 hours)");
        vm.prank(contributor1);
        piePay.submitContribution(30, 1, "Updated documentation (0.5 hours)");
        
        assertContribution(1, 480, 3, "Implemented new feature (8 hours)", 
         PiePay.ContributionStatus.Pending, contributor1, 0);
        assertContribution(2, 120, 5, "Fixed that tricky bug (2 hours)",
         PiePay.ContributionStatus.Pending, contributor1, 0);
        assertContribution(3, 30, 1, "Updated documentation (0.5 hours)",
         PiePay.ContributionStatus.Pending, contributor1, 0);


        vm.prank(contributor2);
        piePay.submitContribution(240, 4, "Implemented complex new feature (4 hours)");
        vm.prank(contributor2);
        piePay.submitContribution(60, 3, "Fixed that simple bug (1 hours)");
        vm.prank(contributor2);
        piePay.submitContribution(15, 2, "Updated documentation (0.5 hours)");

        assertContribution(4, 240, 4, "Implemented complex new feature (4 hours)", 
         PiePay.ContributionStatus.Pending, contributor2, 0);
        assertContribution(5, 60, 3, "Fixed that simple bug (1 hours)",
         PiePay.ContributionStatus.Pending, contributor2, 0);
        assertContribution(6, 15, 2, "Updated documentation (0.5 hours)",
         PiePay.ContributionStatus.Pending, contributor2, 0);
    }

    function testReviewManyContributions() public {
        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(120, 1, "Implemented new feature 1");
        assertContribution(
            1, 
            120, 
            1, 
            "Implemented new feature 1", 
            PiePay.ContributionStatus.Pending, 
            contributor1, 
            0
        );

        vm.prank(contributor1);
        piePay.submitContribution(240, 2, "Implemented new feature 2");
        assertContribution(
            2, 
            240, 
            2, 
            "Implemented new feature 2", 
            PiePay.ContributionStatus.Pending, 
            contributor1, 
            0
        );

        vm.prank(contributor1);
        piePay.submitContribution(480, 3, "Implemented new feature 3");
        assertContribution(
            3, 
            480, 
            3, 
            "Implemented new feature 3", 
            PiePay.ContributionStatus.Pending, 
            contributor1, 
            0
        );
        
        vm.prank(contributor1);
        piePay.submitContribution(960, 4, "Implemented new feature 4");
        assertContribution(
            4, 
            960, 
            4, 
            "Implemented new feature 4", 
            PiePay.ContributionStatus.Pending, 
            contributor1, 
            0
        );

        vm.prank(contributor1);
        piePay.submitContribution(1920, 5, "Implemented new feature 5");
        assertContribution(
            5, 
            1920, 
            5, 
            "Implemented new feature 5", 
            PiePay.ContributionStatus.Pending, 
            contributor1, 
            0
        );

        //Pull valuation factors from the contract
       (uint256 factor1, uint256 factor2, uint256 factor3, uint256 factor4, uint256 factor5) = 
        piePay.valuationRubric();

        // Approve contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Great work 1!");
        assertContribution(
            1, //1st contribution
            120, //2 hours (120 minutes)
            1, // valuation factor 1
            "Implemented new feature 1", 
            PiePay.ContributionStatus.Approved, 
            contributor1, 
            120 * factor1 // 120 minutes * factor1 rate
        );

        vm.prank(projectLead);
        piePay.reviewContribution(2, false, "Rejected 2!");
        assertContribution(
            2, 
            240, 
            2, 
            "Implemented new feature 2", 
            PiePay.ContributionStatus.Rejected, 
            contributor1, 
            0 
        );

        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Wait nevermind 2!");
        assertContribution(
            2, 
            240, 
            2, 
            "Implemented new feature 2", 
            PiePay.ContributionStatus.Approved, 
            contributor1, 
            240 * factor2 
        );

        vm.prank(projectLead);
        piePay.reviewContribution(4, true, "Great work 4!");
        assertContribution(
            4, 
            960, 
            4, 
            "Implemented new feature 4", 
            PiePay.ContributionStatus.Approved, 
            contributor1, 
            960 * factor4 
        );

        vm.prank(projectLead);
        vm.expectRevert("Contribution already approved");
        piePay.reviewContribution(4, false, "Actually, rejected!");


        vm.prank(projectLead);
        piePay.reviewContribution(5, false, "Rejected 5!");  
        assertContribution(
            5, // 5th contribution
            1920, // 32 hours (1920 minutes)
            5, // valuation factor 5
            "Implemented new feature 5", 
            PiePay.ContributionStatus.Rejected, 
            contributor1, 
            0 
        );

        assertContribution(
            5, // 5th contribution
            1920, // 32 hours (1920 minutes)
            5, // valuation factor 5
            "Implemented new feature 5", 
            PiePay.ContributionStatus.Rejected, 
            contributor1, 
            0 
        );
    }

    function assertContribution(
        uint256 contributionId,
        uint256 expectedMinutes,
        uint8 expectedFactor,
        string memory expectedDescription,
        PiePay.ContributionStatus expectedStatus,
        address expectedContributor,
        uint256 expectedPUnits
    ) internal {
        (uint256 minutesWorked, uint8 factor, string memory description, 
         PiePay.ContributionStatus status, , 
         address contributor, , uint256 pUnits) = piePay.contributions(contributionId);
        
        assertEq(minutesWorked, expectedMinutes);
        assertEq(factor, expectedFactor);
        assertEq(description, expectedDescription);
        assertEq(uint(status), uint(expectedStatus));
        assertEq(contributor, expectedContributor);
        assertEq(pUnits, expectedPUnits);
    }
    
    function testFundPayrollWithUSDC() public {
        uint256 fundAmount = 1000 * 10**6; // $1000 USDC (6 decimals)
        
        // Check initial balances
        assertEq(usdc.balanceOf(payrollManager), 10000 * 10**6);
        assertEq(usdc.balanceOf(address(piePay)), 0);
        assertEq(piePay.payrollPool(), 0);
        
        // Payroll manager approves PiePay to spend USDC
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        
        // Fund payroll
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Check balances after funding
        assertEq(usdc.balanceOf(payrollManager), 9000 * 10**6); // 1000 USDC spent
        assertEq(usdc.balanceOf(address(piePay)), fundAmount);   // Contract received USDC
        assertEq(piePay.payrollPool(), 1000e6);        
    }
    
    function testFundPayrollRequiresApproval() public {
        uint256 fundAmount = 1000 * 10**6;
        
        // Try to fund without approval (should fail)
        vm.prank(payrollManager);
        vm.expectRevert(); // ERC20 transfer will revert due to insufficient allowance
        piePay.fundPayroll(fundAmount);
    }

    function testFundPayrollOnlyPayrollManager() public {
        uint256 fundAmount = 1000 * 10**6;
        
        // Give contributor1 some USDC and try to fund
        usdc.mint(contributor1, fundAmount);
        
        vm.prank(contributor1);
        usdc.approve(address(piePay), fundAmount);
        
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.fundPayroll(fundAmount);
    }
    
    function testFundPayrollZeroAmount() public {
        vm.prank(payrollManager);
        vm.expectRevert("Amount must be greater than 0");
        piePay.fundPayroll(0);
    }

    function testFundPayrollInsufficientBalance() public {
        uint256 fundAmount = 20000 * 10**6; // More than payrollManager has
        
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert(); // ERC20 transfer will revert due to insufficient balance
        piePay.fundPayroll(fundAmount);
    }

    function testFundPayrollEmitsEvent() public {
        uint256 fundAmount = 1000 * 10**6;
        
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        
        // Expect the event with normalized amount (18 decimals)
        vm.expectEmit(true, false, false, true);
        emit PayrollFunded(1000e6);
        
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
    }

    function testMultipleFundingRounds() public {
        // First funding round
        vm.prank(payrollManager);
        usdc.approve(address(piePay), 500 * 10**6);
        vm.prank(payrollManager);
        piePay.fundPayroll(500 * 10**6);
        
        assertEq(piePay.payrollPool(), 500e6);
        
        // Second funding round
        vm.prank(payrollManager);
        usdc.approve(address(piePay), 300 * 10**6);
        vm.prank(payrollManager);
        piePay.fundPayroll(300 * 10**6);
        
        assertEq(piePay.payrollPool(), 800e6); // 500 + 300
        assertEq(usdc.balanceOf(address(piePay)), 800 * 10**6);
    }
    
    function testWhitelistNewContributor() public {
        address newContributor = makeAddr("newContributor");
        
        vm.prank(projectLead);
        piePay.whitelistContributor(newContributor);
        
        assertTrue(piePay.whitelistedContributors(newContributor));
        assertEq(piePay.getContributorCount(), 3);
    }
    
    function testRemoveContributor() public {
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        assertFalse(piePay.whitelistedContributors(contributor1));
        assertEq(piePay.getContributorCount(), 1);
    }
    
    function testOnlyProjectLeadCanReviewContributions() public {
        vm.prank(contributor1);
        piePay.submitContribution(8, 3, "Test contribution");
        
        // Try to review as non-project-lead (should fail)
        vm.prank(contributor2);
        vm.expectRevert("Not the project lead");
        piePay.reviewContribution(1, true, "Unauthorized review");
    }
    
    function testOnlyWhitelistedCanSubmitContributions() public {
        address nonContributor = makeAddr("nonContributor");
        
        vm.prank(nonContributor);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.submitContribution(8, 3, "Unauthorized contribution");
    }
    
    function testOnlyPayrollManagerCanFundPayroll() public {
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.fundPayroll(1000e18);
    }
    
    function testGetPendingContributions() public {
        // Submit multiple contributions
        vm.prank(contributor1);
        piePay.submitContribution(8, 3, "Contribution 1");
        
        vm.prank(contributor2);
        piePay.submitContribution(4, 4, "Contribution 2");
        
        vm.prank(contributor1);
        piePay.submitContribution(6, 2, "Contribution 3");
        
        uint256[] memory pendingIds = piePay.getPendingContributions();
        assertEq(pendingIds.length, 3);
        assertEq(pendingIds[0], 1);
        assertEq(pendingIds[1], 2);
        assertEq(pendingIds[2], 3);
        
        // Approve one contribution
        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Approved");
        
        // Check pending contributions again
        pendingIds = piePay.getPendingContributions();
        assertEq(pendingIds.length, 2);
    }

    function testFundPayroll() public {

        uint256 fundAmount = 1000 * 10**6;

        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount); // Approve PiePay to spend USDC

        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount); // Fund with $1000
        
        (, , uint256 availableFunds, ) = piePay.getCurrentDistributionInfo();
        assertEq(availableFunds, 1000e6); // 1000 USDC in payroll pool
    }
    
    // Add these new test functions to your existing PiePayTest contract

    function testExecutePUnitPayoutBasic() public {
        // Setup contributions and approve them
        vm.prank(contributor1);
        piePay.submitContribution(600, 3, "10 hours work"); // 600 minutes = 10 hours. VL3 = $60/hr. 600 P Units uses e18
        
        vm.prank(contributor2);
        piePay.submitContribution(240, 3, "4 hours work"); // 240 minutes * 100e18 = 240 P-Units uses e18
        
        // Approve both contributions
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Approved");
        
        // Fund payroll with enough USDC to pay everyone
        uint256 fundAmount = 840 * 10**6; // 8400 USDC (enough for 8400 P-Units)
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Record initial balances
        uint256 initialBalance1 = usdc.balanceOf(contributor1);
        uint256 initialBalance2 = usdc.balanceOf(contributor2);
        uint256 initialContractBalance = usdc.balanceOf(address(piePay));
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Check that all P-Units were reset to 0
        (uint256 pUnits1,,) = piePay.getContributorUnits(contributor1);
        (uint256 pUnits2,,) = piePay.getContributorUnits(contributor2);
        assertEq(pUnits1, 0, "Contributor1 P-Units should be reset to 0");
        assertEq(pUnits2, 0, "Contributor2 P-Units should be reset to 0");
        
        // Check final balances - contributor1 should get 6000 USDC, contributor2 should get 2400 USDC
        uint256 finalBalance1 = usdc.balanceOf(contributor1);
        uint256 finalBalance2 = usdc.balanceOf(contributor2);
        
        // Contributor1 is first active, so they get any rounding dust
        assertGe(finalBalance1 - initialBalance1, 600 * 10**6, "Contributor1 should receive at least 600 USDC");
        assertEq(finalBalance2 - initialBalance2, 240 * 10**6, "Contributor2 should receive exactly 240 USDC");
        
        // Total distributed should equal initial contract balance
        uint256 totalDistributed = (finalBalance1 - initialBalance1) + (finalBalance2 - initialBalance2);
        assertEq(totalDistributed, initialContractBalance, "Total distributed should equal initial contract balance");
        
        // Contract should have 0 USDC remaining
        assertEq(usdc.balanceOf(address(piePay)), 0, "Contract should have 0 USDC remaining");
    }

    function testExecutePUnitPayoutPartialFunding() public {
        // Setup contributions with total 6000 P-Units
        vm.prank(contributor1);
        piePay.submitContribution(400, 3, "Work 1"); // 400e18 P-Units
        
        vm.prank(contributor2);
        piePay.submitContribution(200, 3, "Work 2"); // 200e18 P-Units
        
        // Approve both
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Approved");
        
        // Fund with only half the needed amount
        uint256 fundAmount = 300 * 10**6; // Only 300 USDC for 6000 P-Units
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Check distributions are proportional to available funds
        // Contributor1: 4000/6000 * 3000 = 2000 USDC
        // Contributor2: 2000/6000 * 3000 = 1000 USDC
        uint256 balance1 = usdc.balanceOf(contributor1);
        uint256 balance2 = usdc.balanceOf(contributor2);
        
        assertGe(balance1, 200 * 10**6, "Contributor1 should receive at least 200 USDC");
        assertEq(balance2, 100 * 10**6, "Contributor2 should receive exactly 100 USDC");
        
        assertEq(balance1 + balance2, 300 * 10**6, "Total distributed should be 300 USDC");

        // Contract should have 0 USDC remaining
        assertEq(usdc.balanceOf(address(piePay)), 0, "Contract should have 0 USDC remaining");
    }

    function testExecutePUnitPayoutWithZeroPUnits() public {
        // Only contributor1 has P-Units, contributor2 has none
        vm.prank(contributor1);
        piePay.submitContribution(100, 3, "Solo work"); // 100e18 P-Units
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        // Fund payroll
        uint256 fundAmount = 2000 * 10**6;
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Only contributor1 should receive tokens
        assertEq(usdc.balanceOf(contributor1), 100 * 10**6, "Contributor1 should receive all USDC");
        assertEq(usdc.balanceOf(contributor2), 0, "Contributor2 should receive no USDC");
    }

    function testExecutePUnitPayoutRoundingPrecision() public {
        // Create scenario that will cause rounding issues
        vm.prank(contributor1);
        piePay.submitContribution(333, 3, "Work 1"); // 3330e18 P-Units
        
        vm.prank(contributor2);
        piePay.submitContribution(667, 3, "Work 2"); // 6670e18 P-Units
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Approved");
        
        // Fund with amount that will cause rounding
        uint256 fundAmount = 999 * 10**6; // 999 USDC for 10000 P-Units
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        uint256 initialBalance1 = usdc.balanceOf(contributor1);
        uint256 initialBalance2 = usdc.balanceOf(contributor2);
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        uint256 received1 = usdc.balanceOf(contributor1) - initialBalance1;
        uint256 received2 = usdc.balanceOf(contributor2) - initialBalance2;
        
        // Total should equal exactly what was funded
        assertEq(received1 + received2, 999 * 10**6, "Total distributed should equal funded amount");
        
        // First contributor gets rounding dust, so they might get slightly more than their exact share
        uint256 expectedShare2 = (6670 * 999 * 10**6) / 10000; // Exact share for contributor2
        assertEq(received2, expectedShare2, "Contributor2 should get exact calculated share");
    }

    function testExecutePUnitPayoutFailureConditions() public {
        // Test no contributors
        // (Can't easily test this since we have initial contributors)
        
        // Test no active contributors (no P-Units)
        uint256 fundAmount = 1000 * 10**6;
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert("No active contributors");
        piePay.executePUnitPayout();
    }

    function testExecutePUnitPayoutNoFunds() public {
        // Setup P-Units but no funding
        vm.prank(contributor1);
        piePay.submitContribution(100, 3, "Work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        // Try to execute without funding
        vm.prank(payrollManager);
        vm.expectRevert("No funds available");
        piePay.executePUnitPayout();
    }

    function testExecutePUnitPayoutInsufficientTokenBalance() public {
        // Setup P-Units normally
        vm.prank(contributor1);
        piePay.submitContribution(100, 3, "Work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        // Fund payroll with insufficient amount
        vm.prank(payrollManager);
        usdc.approve(address(piePay), 50 * 10**6); // Only fund 50 USDC when 100 is needed
        vm.prank(payrollManager);
        piePay.fundPayroll(50 * 10**6);
        
        // Should fail due to insufficient token balance
        vm.prank(payrollManager);
        piePay.executePUnitPayout();

        // Check payroll pool is reduced
        assertEq(piePay.payrollPool(), 0, "Payroll pool should be 0 after full payout");
        
        // Check distribution counter incremented
        assertEq(piePay.distributionCounter(), 1, "Distribution counter should be 1");
    }

    function testExecutePUnitPayoutOnlyPayrollManager() public {
        // Setup some P-Units
        vm.prank(contributor1);
        piePay.submitContribution(100, 3, "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        // Fund
        uint256 fundAmount = 1000 * 10**6;
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Try to execute as non-payroll manager
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.executePUnitPayout();
        
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.executePUnitPayout();
    }

    function testExecutePUnitPayoutUpdatesInternalAccounting() public {
        vm.prank(contributor1);
        piePay.submitContribution(500, 3, "Work"); // 500e18 P-Units
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        uint256 fundAmount = 500 * 10**6;
        vm.prank(payrollManager);
        usdc.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Check initial payroll pool
        assertEq(piePay.payrollPool(), 500e6, "Initial payroll pool should be 500e6");
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Check payroll pool is reduced
        assertEq(piePay.payrollPool(), 0, "Payroll pool should be 0 after full payout");
        
        // Check distribution counter incremented
        assertEq(piePay.distributionCounter(), 1, "Distribution counter should be 1");
    }

    function testExecutePUnitPayoutMultipleDistributions() public {
        // First distribution
        vm.prank(contributor1);
        piePay.submitContribution(100, 3, "Work 1");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true, "Approved");
        
        vm.prank(payrollManager);
        usdc.approve(address(piePay), 100 * 10**6);
        vm.prank(payrollManager);
        piePay.fundPayroll(100 * 10**6);
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        uint256 balance1AfterFirst = usdc.balanceOf(contributor1);
        assertEq(balance1AfterFirst, 100 * 10**6, "First distribution should give 1000 USDC");
        
        // Second distribution
        vm.prank(contributor2);
        piePay.submitContribution(200, 3, "Work 2");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true, "Approved");
        
        vm.prank(payrollManager);
        usdc.approve(address(piePay), 200 * 10**6);
        vm.prank(payrollManager);
        piePay.fundPayroll(200 * 10**6);
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Balances should be correct
        assertEq(usdc.balanceOf(contributor1), 100 * 10**6, "Contributor1 balance unchanged");
        assertEq(usdc.balanceOf(contributor2), 200 * 10**6, "Contributor2 gets 200 USDC");
        assertEq(piePay.distributionCounter(), 2, "Should have 2 distributions");
    }

}