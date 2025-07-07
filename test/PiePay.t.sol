// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PiePay.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockDAI.sol";
import "./mocks/IMintableToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



abstract contract PiePayTest is Test {
    PiePay public piePay;
    IMintableToken public coin;
    
    address public owner;
    address public projectLead;
    address public payrollManager;
    address public contributor1;
    address public contributor2;

    event PayrollFunded(uint256 amount);

    function deployCoin() internal virtual returns (IMintableToken);
    function getCoinAmount(uint256 baseAmount) internal virtual returns (uint256);
    
    function setUp() public virtual{
        owner = address(this);
        projectLead = makeAddr("projectLead");
        payrollManager = makeAddr("payrollManager");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");

        // Deploy mock USDC
         coin = deployCoin();
        
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
            address(coin)
            //0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE //SplitMain address
        );

        // Give payroll manager some USDC
        coin.mint(payrollManager, getCoinAmount(10000)); // 10,000 USDC
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
        piePay.submitContribution(500, "Implemented new feature");
        
        (address contributor, uint256 pUnitsClaimed, PiePay.ContributionStatus status, string memory description) = 
         piePay.contributions(1);
        assertEq(description, "Implemented new feature");
        assertEq(uint(status), uint(PiePay.ContributionStatus.Pending));
        assertEq(contributor, contributor1);
        assertEq(pUnitsClaimed, 500); // Not approved yet
    }

    function testReviewContributionAccepted() public {

        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(605, "Implemented new feature"); //60 minutes @ $60/hr = $60 = 60 P Units
        
        // Reject contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);

        // Check contribution status
        (,uint256 pUnitsClaimed, PiePay.ContributionStatus status,) = 
         piePay.contributions(1);
        
        assertEq(uint(status), uint(PiePay.ContributionStatus.Approved));
        assertEq(605, pUnitsClaimed); // 60 minutes * factor3 rate
        
        (uint256 pUnits, , ) = piePay.getContributorUnits(contributor1);
        assertEq(605, pUnits);
    }


     function testReviewContributionRejected() public {
        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(800, "Implemented new feature");
        
        // Reject contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, false);
        
        // Check contribution status
        (,uint256 pUnitsClaimed, PiePay.ContributionStatus status, ) = 
         piePay.contributions(1);
        
        assertEq(uint(status), uint(PiePay.ContributionStatus.Rejected));
        assertEq(pUnitsClaimed, 800); 
        
        // Check P-Units balance (should be 0)
        uint256 pUnits = piePay.pUnits(contributor1);
        assertEq(pUnits, 0);
    }

    function testSubmitManyContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(1550e18, "a");
        vm.prank(contributor1);
        piePay.submitContribution(1205e18, "b");
        vm.prank(contributor1);
        piePay.submitContribution(305e18, "c");

        assertContribution(1, "a", 
        PiePay.ContributionStatus.Pending, contributor1, 1550e18);
        assertContribution(2, "b",
        PiePay.ContributionStatus.Pending, contributor1, 1205e18);
        assertContribution(3,"c",
        PiePay.ContributionStatus.Pending, contributor1, 305e18);
        assertEq(piePay.pUnits(contributor1), 0); //no real PUnits yet

        vm.prank(contributor2);
        piePay.submitContribution(2400e18, "e");
        vm.prank(contributor2);
        piePay.submitContribution(600e18, "f");
        vm.prank(contributor2);
        piePay.submitContribution(150e18, "g");

        assertContribution(4,"e", 
        PiePay.ContributionStatus.Pending, contributor2, 2400e18);
        assertContribution(5,"f",
        PiePay.ContributionStatus.Pending, contributor2, 600e18);
        assertContribution(6,"g",
        PiePay.ContributionStatus.Pending, contributor2, 150e18);
        assertEq(piePay.pUnits(contributor2), 0); //no real PUnits yet
    }

    function testReviewManyContributions() public {
        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(120e18, "Implemented new feature 1");
        assertContribution(
            1, "Implemented new feature 1", 
            PiePay.ContributionStatus.Pending, contributor1,  120e18
        );
        assertEq(piePay.pUnits(contributor1), 0);

        vm.prank(contributor1);
        piePay.submitContribution(240e18, "Implemented new feature 2");
        assertContribution(
            2, "Implemented new feature 2", 
            PiePay.ContributionStatus.Pending, contributor1,  240e18
        );

        vm.prank(contributor1);
        piePay.submitContribution(480e18, "Implemented new feature 3");
        assertContribution(
            3, "Implemented new feature 3", 
            PiePay.ContributionStatus.Pending, contributor1,  480e18
        );
        
        vm.prank(contributor1);
        piePay.submitContribution(960e18, "Implemented new feature 4");
        assertContribution(
            4, "Implemented new feature 4", 
            PiePay.ContributionStatus.Pending, contributor1,  960e18
        );

        vm.prank(contributor1);
        piePay.submitContribution(1920e18, "Implemented new feature 5");
        assertContribution(
            5, "Implemented new feature 5", 
            PiePay.ContributionStatus.Pending, contributor1,  1920e18);

        // Approve contribution
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        assertContribution(
            1, "Implemented new feature 1", 
            PiePay.ContributionStatus.Approved, contributor1,  120e18);
        assertEq(piePay.pUnits(contributor1), 120e18); // 120 P-Units

        vm.prank(projectLead);
        piePay.reviewContribution(2, false);
        assertContribution(
            2, "Implemented new feature 2", 
            PiePay.ContributionStatus.Rejected, contributor1,  240e18
        );
        assertEq(piePay.pUnits(contributor1), 120e18, "assert no change in pUnits after rejection"); 

        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        assertContribution(
            2, "Implemented new feature 2", 
            PiePay.ContributionStatus.Approved, contributor1, 240e18
        );
        assertEq(piePay.pUnits(contributor1), 360e18); 

        vm.prank(projectLead);
        piePay.reviewContribution(4, true);
        assertContribution(
            4, "Implemented new feature 4", 
            PiePay.ContributionStatus.Approved, contributor1, 960e18
        );
        assertEq(piePay.pUnits(contributor1), 1320e18); 
        
        vm.prank(projectLead);
        vm.expectRevert("Contribution already approved");
        piePay.reviewContribution(4, false);


        vm.prank(projectLead);
        piePay.reviewContribution(5, false);  
        assertContribution(
            5, "Implemented new feature 5", 
            PiePay.ContributionStatus.Rejected, contributor1, 1920e18
        );
    }
    
    function testFundPayrollWithUSDC() public {
        uint256 fundAmount = getCoinAmount(1000); 
        
        // Check initial balances
        assertEq(coin.balanceOf(payrollManager), getCoinAmount(10000));
        assertEq(coin.balanceOf(address(piePay)), 0);
        assertEq(piePay.payrollPool(), 0);
        
        // Payroll manager approves  to spend USDC
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        
        // Fund payroll
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Check balances after funding
        assertEq(coin.balanceOf(payrollManager), getCoinAmount(9000)); // 1000 coin spent
        assertEq(coin.balanceOf(address(piePay)), fundAmount);   // Contract received right coin
        assertEq(piePay.payrollPool(), getCoinAmount(1000));        
    }
    
    function testFundPayrollRequiresApproval() public {
        uint256 fundAmount = 1000 * 10**6;
        
        // Try to fund without approval (should fail)
        vm.prank(payrollManager);
        vm.expectRevert(); // ERC20 transfer will revert due to insufficient allowance
        piePay.fundPayroll(fundAmount);
    }

    function testFundPayrollOnlyPayrollManager() public {
        uint256 fundAmount = getCoinAmount(1000);
        
        // Give contributor1 some USDC and try to fund
        coin.mint(contributor1, fundAmount);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), fundAmount);
        
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
        uint256 fundAmount = getCoinAmount(20000); // More than payrollManager has
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert(); // ERC20 transfer will revert due to insufficient balance
        piePay.fundPayroll(fundAmount);
    }

    function testFundPayrollEmitsEvent() public {
        uint256 fundAmount = getCoinAmount(1000);
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        
        // Expect the event with normalized amount (18 decimals)
        vm.expectEmit(true, false, false, true);
        emit PayrollFunded(getCoinAmount(1000));
        
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
    }

    function testMultipleFundingRounds() public {
        // First funding round
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(500));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(500));
        
        assertEq(piePay.payrollPool(), getCoinAmount(500));
        
        // Second funding round
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(300));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(300));
        
        assertEq(piePay.payrollPool(), getCoinAmount(800)); // 500 + 300
        assertEq(coin.balanceOf(address(piePay)), getCoinAmount(800));
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
        piePay.submitContribution(800, "Test contribution");
        
        // Try to review as non-project-lead (should fail)
        vm.prank(contributor2);
        vm.expectRevert("Not the project lead");
        piePay.reviewContribution(1, true);
    }
    
    function testOnlyWhitelistedCanSubmitContributions() public {
        address nonContributor = makeAddr("nonContributor");
        
        vm.prank(nonContributor);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.submitContribution(800, "Unauthorized contribution");
    }
    
    function testOnlyPayrollManagerCanFundPayroll() public {
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.fundPayroll(1000e18);
    }
    
    function testFundPayroll() public {

        uint256 fundAmount = getCoinAmount(1000);

        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount); // Approve  to spend USDC

        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount); // Fund with $1000
        
        (, , uint256 availableFunds, ) = piePay.getCurrentDistributionInfo();
        assertEq(availableFunds, getCoinAmount(1000)); // 1000 USDC in payroll pool
    }
  
    function testExecutePUnitPayoutBasic() public {
        // Setup contributions
        vm.prank(contributor1);
        piePay.submitContribution(600e18, "a"); 
        vm.prank(contributor2);
        piePay.submitContribution(240e18, "b"); 
        
        // Approve both contributions
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund payroll with enough USDC to pay everyone
        uint256 fundAmount = getCoinAmount(840);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);


        // Record initial balances
        uint256 pUnits1 = piePay.pUnits(contributor1);
        uint256 pUnits2 = piePay.pUnits(contributor2);
        uint256 initialBalance1 = coin.balanceOf(contributor1);
        uint256 initialBalance2 = coin.balanceOf(contributor2);
        uint256 initialContractBalance = coin.balanceOf(address(piePay));


        assertEq(piePay.pUnits(contributor1), 600e18, "Contributor1 P-Units should be 600");
        assertEq(piePay.pUnits(contributor2), 240e18, "Contributor2 P-Units should be 240");
        assertEq(initialBalance1, 0, "Contributor1 balance should be 0");
        assertEq(initialBalance2, 0, "Contributor2 balance should be 0");
        assertEq(initialContractBalance, fundAmount, "piePay balance should be 840");
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        uint256 finalPUnits1 = piePay.pUnits(contributor1);
        uint256 finalPUnits2 = piePay.pUnits(contributor2);
        uint256 finalBalance1 = coin.balanceOf(contributor1);
        uint256 finalBalance2 = coin.balanceOf(contributor2);
        uint256 finalContractBalance = coin.balanceOf(address(piePay));
        assertEq(finalPUnits1, 0, "Contributor1 P-Units should be reset to 0");
        assertEq(finalPUnits2, 0, "Contributor2 P-Units should be reset to 0");
        assertEq(finalBalance1, getCoinAmount(600), "Contributor1 balance should be 600");
        assertEq(finalBalance2, getCoinAmount(240), "Contributor2 balance should be 240");
        assertEq(finalContractBalance, 0, "piePay balance should be 0");

        
        // Contributor1 is first active, so they get any rounding dust
        assertGe(finalBalance1 - initialBalance1, getCoinAmount(600), "Contributor1 should receive at least 600 USDC");
        assertEq(finalBalance2 - initialBalance2, getCoinAmount(240), "Contributor2 should receive exactly 240 USDC");
        
        // Total distributed should equal initial contract balance
        uint256 totalDistributed = (finalBalance1 - initialBalance1) + (finalBalance2 - initialBalance2);
        assertEq(totalDistributed, initialContractBalance, "Total distributed should equal initial contract balance");
        
        // Contract should have 0 USDC remaining
        assertEq(coin.balanceOf(address(piePay)), 0, "Contract should have 0 USDC remaining");
    }

    function testExecutePUnitPayoutPartialFunding() public {
        // Setup contributions with total 6000 P-Units
        vm.prank(contributor1);
        piePay.submitContribution(400e18, "Work 1"); // 400e18 P-Units
        
        vm.prank(contributor2);
        piePay.submitContribution(200e18, "Work 2"); // 200e18 P-Units
        
        // Approve both
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund with only half the needed amount
        uint256 fundAmount = getCoinAmount(300); // Only 300 USDC for 600 P-Units
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Check distributions are proportional to available funds
        // Contributor1: 400/600 * 300 = 200 USDC
        // Contributor2: 200/600 * 300 = 100 USDC
        assertGe(coin.balanceOf(contributor1), getCoinAmount(200), "Contributor1 should receive at least 200 USDC");
        assertEq(coin.balanceOf(contributor2), getCoinAmount(100), "Contributor2 should receive exactly 100 USDC");

        // Contract should have 0 USDC remaining
        assertEq(coin.balanceOf(address(piePay)), 0, "Contract should have 0 USDC remaining");
    }

    function testExecutePUnitPayoutWithZeroPUnits() public {
        // Only contributor1 has P-Units, contributor2 has none
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Solo work"); // 100e18 P-Units
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund payroll
        uint256 fundAmount = getCoinAmount(2000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Execute payout
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Only contributor1 should receive tokens
        assertEq(coin.balanceOf(contributor1), getCoinAmount(100), "Contributor1 should receive all USDC");
        assertEq(coin.balanceOf(contributor2), 0, "Contributor2 should receive no USDC");
    }

    function testExecutePUnitPayoutRoundingPrecision() public {
    // Create scenario that will cause rounding issues
    vm.prank(contributor1);
    piePay.submitContribution(333e18, "Work 1"); // 333e18 P-Units
    console.log("test:contributor1", contributor1);
    vm.prank(contributor2);
    piePay.submitContribution(666e18, "Work 2"); // 666e18 P-Units
    console.log("test:contributor2", contributor2);

    vm.prank(projectLead);
    piePay.reviewContribution(1, true);
    vm.prank(projectLead);
    piePay.reviewContribution(2, true);
    
    // Fund with amount that will cause rounding
    uint256 fundAmount = getCoinAmount(100); // 100 tokens for 999e18 P-Units
    vm.prank(payrollManager);
    coin.approve(address(piePay), fundAmount);
    vm.prank(payrollManager);
    piePay.fundPayroll(fundAmount);

    // Store initial P-Unit balances
    uint256 initialPUnits1 = piePay.pUnits(contributor1); // 333e18
    uint256 initialPUnits2 = piePay.pUnits(contributor2); // 666e18
    uint256 totalPUnits = initialPUnits1 + initialPUnits2; // 999e18
    
    vm.prank(payrollManager);
    piePay.executePUnitPayout();
    
    uint256 received1 = coin.balanceOf(contributor1);
    uint256 received2 = coin.balanceOf(contributor2);
    console.log("test:received1", received1);
    console.log("test:received2", received2);
    
    // Total should equal exactly what was funded
    assertEq(received1 + received2, fundAmount, "Total distributed should equal funded amount");

    // Calculate expected shares (with proper precision)
    uint256 fundAmountInternal = 100e18; // 100 tokens converted to internal 18 decimals
    uint256 expectedShare1Internal = (initialPUnits1 * fundAmountInternal) / totalPUnits;
    uint256 expectedShare2Internal = (initialPUnits2 * fundAmountInternal) / totalPUnits;
    
    // Get the conversion factor from internal (18 decimals) to token decimals
    uint256 tokenDecimals = coin.decimals();
    uint256 conversionFactor = 10**(18 - tokenDecimals);
    
    // Convert expected shares back to token amounts for verification
    uint256 expectedReceived1 = expectedShare1Internal / conversionFactor;
    uint256 expectedReceived2 = expectedShare2Internal / conversionFactor;

    // Due to rounding, contributor1 gets the remaining dust
    uint256 calculatedRemaining = fundAmount - expectedReceived2;

    assertEq(received1, calculatedRemaining, "Contributor1 should get calculated remaining amount");
    assertEq(received2, expectedReceived2, "Contributor2 should get exact calculated share");

    // Check P-Unit balances are reduced by the correct internal amounts
    assertEq(piePay.pUnits(contributor1), initialPUnits1 - (calculatedRemaining * conversionFactor), "Contributor1 P-Units should be reduced by converted remaining amount");
    assertEq(piePay.pUnits(contributor2), initialPUnits2 - expectedShare2Internal, "Contributor2 P-Units should be reduced by exact calculated share");
    
    // Verify the math checks out
    console.log("Token decimals:", tokenDecimals);
    console.log("Conversion factor:", conversionFactor);
    console.log("Expected share 1 (internal):", expectedShare1Internal);
    console.log("Expected share 2 (internal):", expectedShare2Internal);
    console.log("Calculated remaining tokens:", calculatedRemaining);
    console.log("Expected received 2:", expectedReceived2);
}
    
    function testExecutePUnitPayoutFailureConditions() public {
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert("No active contributors");
        piePay.executePUnitPayout();
    }

    function testExecutePUnitPayoutNoFunds() public {
        // Setup P-Units but no funding
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Try to execute without funding
        vm.prank(payrollManager);
        vm.expectRevert("No funds available");
        piePay.executePUnitPayout();
    }

    function testExecutePUnitPayoutInsufficientTokenBalance() public {
        // Setup P-Units normally
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund payroll with insufficient amount
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(50)); // Only fund 50 USDC when 100 is needed
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(50));
        
        // Should fail due to insufficient token balance
        vm.prank(payrollManager);
        piePay.executePUnitPayout();

        // Check payroll pool is reduced
        assertEq(piePay.payrollPool(), 0, "Payroll pool should be 0 after full payout");
        assertEq(coin.balanceOf(contributor1), getCoinAmount(50), "Contributor1 should receive 50 USDC");
        assertEq(piePay.pUnits(contributor1), 50e18, "Contributor1 should still have 50 PUnits");
        // Check distribution counter incremented
        assertEq(piePay.distributionCounter(), 1, "Distribution counter should be 1");
    }

    function testExecutePUnitPayoutOnlyPayrollManager() public {
        // Setup some P-Units
        vm.prank(contributor1);
        piePay.submitContribution(100, "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
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
        piePay.submitContribution(500e18, "Work"); // 500e18 P-Units
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Check initial payroll pool
        assertEq(piePay.payrollPool(), getCoinAmount(500), "Initial payroll pool should be 500e6");
        
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
        piePay.submitContribution(100e18, "Work 1");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(50));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(50));
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        assertEq(coin.balanceOf(contributor1), getCoinAmount(50), "First distribution should give 50 USDC");
        assertEq(piePay.pUnits(contributor1), 50e18, "P-Units should be 50 after payout");
        assertEq(coin.balanceOf(address(piePay)), 0, "PiePay should have 0 USDC after payout");
        // Second distribution
        vm.prank(contributor2);
        piePay.submitContribution(200e18, "Work 2");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(200));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(200));
        
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Balances should be correct
        assertEq(coin.balanceOf(contributor1), getCoinAmount(50) + getCoinAmount(40), "Contributor1 receives 40 USDC from second distribution");
        assertEq(coin.balanceOf(contributor2), getCoinAmount(160), "Contributor2 gets 160 USDC");
        assertEq(coin.balanceOf(address(piePay)), 0, "PiePay should have 0 USDC after payout");
        assertEq(piePay.distributionCounter(), 2, "Should have 2 distributions");
    }

    // ============ D UNIT TESTS ============

    function testGrantDUnits() public {
        // Project lead grants D units for unpaid work
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 500e18, "Unpaid overtime work");
        
        // Check D unit balance
        (,uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, 500e18, "Contributor1 should have 500 D units");
        
        // Check total D units across all contributors
        (,uint256 totalDUnits,,) = piePay.getCurrentDistributionInfo();
        assertEq(totalDUnits, 500e18, "Total D units should be 500");
    }

    function testGrantDUnitsOnlyPayrollManager() public {
        // Non-project lead tries to grant D units
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.grantDUnits(contributor1, 100e18, "Unauthorized grant");
        
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.grantDUnits(contributor2, 1, "Unauthorized grant");
    }

    function testGrantDUnitsToNonWhitelistedContributor() public {
        address outsider = makeAddr("outsider");
        
        vm.prank(payrollManager);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.grantDUnits(outsider, 100e18, "Grant to outsider");
    }

    function testPurchaseDUnitsBasic() public {
        uint256 paymentAmount = getCoinAmount(1000); // Pay $1000
        uint256 multiplier = 1; // 1:1 ratio
        
        // Give contributor1 some tokens to purchase with
        coin.mint(contributor1, paymentAmount);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), paymentAmount);
        
        vm.prank(contributor1);
        piePay.purchaseDUnits(paymentAmount, multiplier);
        
        // Check D unit balance (should be 1000 D units for $1000 at 1x multiplier)
        (,uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, 1000e18, "Should have 1000 D units");
        
        // Check contract received the payment
        assertEq(coin.balanceOf(address(piePay)), paymentAmount, "Contract should receive payment");
        assertEq(piePay.payrollPool(), paymentAmount, "Payment should be added to payroll pool");
    }

    function testPurchaseDUnitsWithMultiplier() public {
        uint256 paymentAmount = getCoinAmount(500); // Pay $500
        uint256 multiplier = 4; // 4:1 ratio
        
        coin.mint(contributor1, paymentAmount);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), paymentAmount);
        
        vm.prank(contributor1);
        piePay.purchaseDUnits(paymentAmount, multiplier);
        
        // Check D unit balance (should be 2000 D units for $500 at 4x multiplier)
        (,uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, 2000e18, "Should have 2000 D units (500 * 4)");
        
        // Contract still only receives the actual payment
        assertEq(coin.balanceOf(address(piePay)), paymentAmount, "Contract should receive actual payment");
        assertEq(piePay.payrollPool(), paymentAmount, "Payroll pool should reflect actual payment");
    }

    function testPurchaseDUnitsOnlyWhitelistedContributors() public {
        address outsider = makeAddr("outsider");
        uint256 paymentAmount = getCoinAmount(100);
        
        coin.mint(outsider, paymentAmount);
        
        vm.prank(outsider);
        coin.approve(address(piePay), paymentAmount);
        
        vm.prank(outsider);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.purchaseDUnits(paymentAmount, 1);
    }

    function testExecuteDUnitPayoutBasic() public {
        // Setup: Give contributors D units
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 600e18, "Past work");
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor2, 400e18, "Past work");
        
        // Fund the contract
        uint256 fundAmount = getCoinAmount(250); // Only $250 for $1000 worth of D units
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Execute D unit payout
        vm.prank(payrollManager);
        piePay.executeDUnitPayout();
        
        // Check proportional distribution
        // Contributor1: 600/1000 * 500 = 300 tokens
        // Contributor2: 400/1000 * 500 = 200 tokens
        assertEq(coin.balanceOf(contributor1), getCoinAmount(150), "Contributor1 should get 150 tokens");
        assertEq(coin.balanceOf(contributor2), getCoinAmount(100), "Contributor2 should get 100 tokens");
        
        // Check D units are reduced (buyback)
        (,uint256 dUnits1,) = piePay.getContributorUnits(contributor1);
        (,uint256 dUnits2,) = piePay.getContributorUnits(contributor2);
        assertEq(dUnits1, 450e18, "Contributor1 should have 300 D units remaining");
        assertEq(dUnits2, 300e18, "Contributor2 should have 200 D units remaining");
        
        // Check payroll pool is depleted
        assertEq(piePay.payrollPool(), 0, "Payroll pool should be empty");
    }

    function testExecuteDUnitPayoutNoFunds() public {
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 100e18, "Work");
        
        vm.prank(payrollManager);
        vm.expectRevert("No funds available");
        piePay.executeDUnitPayout();
    }

    function testExecuteDUnitPayoutNoDUnits() public {
        // Fund but no D units exist
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert("No active D-Unit holders");
        piePay.executeDUnitPayout();
    }

    function testExecuteDUnitPayoutOnlyPayrollManager() public {
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 100e18, "Work");
        
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.executeDUnitPayout();
        
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.executeDUnitPayout();
    }

    function testConvertPUnitsToDebtBasic() public {
        // Setup P units
        vm.prank(contributor1);
        piePay.submitContribution(500e18, "Work1");
        vm.prank(contributor2);
        piePay.submitContribution(300e18, "Work2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Convert P units to D units with 2x multiplier
        address[] memory contributors = new address[](2);
        contributors[0] = contributor1;
        contributors[1] = contributor2;
        
        vm.prank(payrollManager);
        piePay.convertAllPUnitsToDebt(contributors, 2);
        
        // Check P units are zeroed
        assertEq(piePay.pUnits(contributor1), 0, "P units should be 0");
        assertEq(piePay.pUnits(contributor2), 0, "P units should be 0");
        
        // Check D units are created with multiplier
        (,uint256 dUnits1,) = piePay.getContributorUnits(contributor1);
        (,uint256 dUnits2,) = piePay.getContributorUnits(contributor2);
        assertEq(dUnits1, 1000e18, "Should have 1000 D units (500 * 2)");
        assertEq(dUnits2, 600e18, "Should have 600 D units (300 * 2)");
    }

    function testConvertPUnitsToDebtOnlyPayrollManager() public {
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        address[] memory contributors = new address[](1);
        contributors[0] = contributor1;
        
        vm.prank(contributor1);
        vm.expectRevert("Not the payroll manager");
        piePay.convertAllPUnitsToDebt(contributors, 1);
        
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.convertAllPUnitsToDebt(contributors, 1);
    }

    // Add these test functions to your PiePayTest abstract contract:

    function testExecutePUnitPayoutAmountPartial() public {
        // Setup P-Units: contributor1=600, contributor2=240
        vm.prank(contributor1);
        piePay.submitContribution(600e18, "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(240e18, "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund with $1000
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Distribute only $420 (half of the P-Units)
        uint256 distributionAmount = getCoinAmount(420);
        vm.prank(payrollManager);
        piePay.executePUnitPayoutAmount(distributionAmount);
        
        // Check proportional distribution: 420/840 = 50%
        // Contributor1: 600 * 0.5 = 300 USDC received, 300 P-Units remaining
        // Contributor2: 240 * 0.5 = 120 USDC received, 120 P-Units remaining
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300), "Contributor1 should receive at least 300 USDC");
        assertEq(coin.balanceOf(contributor2), getCoinAmount(120), "Contributor2 should receive exactly 120 USDC");
        
        assertEq(piePay.pUnits(contributor1), 300e18, "Contributor1 should have 300 P-Units remaining");
        assertEq(piePay.pUnits(contributor2), 120e18, "Contributor2 should have 120 P-Units remaining");
        
        // Payroll pool should have $580 remaining
        assertEq(piePay.payrollPool(), getCoinAmount(580), "Should have $580 remaining");
    }

    function testExecutePUnitPayoutAmountExceedsAvailable() public {
        // Setup minimal P-Units
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund with $500
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Try to distribute $1000 when only $500 available
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount exceeds available funds");
        piePay.executePUnitPayoutAmount(getCoinAmount(1000));
    }

    function testExecutePUnitPayoutAmountZero() public {
        // Setup and fund
        vm.prank(contributor1);
        piePay.submitContribution(100e18, "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Try to distribute zero amount
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount must be greater than 0");
        piePay.executePUnitPayoutAmount(0);
    }

    function testExecuteDUnitPayoutAmountPartial() public {
        // Setup D-Units
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 600e18, "Unpaid work 1");
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor2, 400e18, "Unpaid work 2");
        
        // Fund with $1000
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Distribute only $500 (half of the D-Units)
        uint256 distributionAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        piePay.executeDUnitPayoutAmount(distributionAmount);
        
        // Check proportional distribution: 500/1000 = 50%
        // Contributor1: 600 * 0.5 = 300 USDC received, 300 D-Units remaining
        // Contributor2: 400 * 0.5 = 200 USDC received, 200 D-Units remaining
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300), "Contributor1 should receive at least 300 USDC");
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200), "Contributor2 should receive exactly 200 USDC");
        
        assertEq(piePay.dUnits(contributor1), 300e18, "Contributor1 should have 300 D-Units remaining");
        assertEq(piePay.dUnits(contributor2), 200e18, "Contributor2 should have 200 D-Units remaining");
        
        // Payroll pool should have $500 remaining
        assertEq(piePay.payrollPool(), getCoinAmount(500), "Should have $500 remaining");
    }

    function testExecuteDUnitPayoutAmountExceedsAvailable() public {
        // Setup D-Units
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 100e18, "Work");
        
        // Fund with $200
        uint256 fundAmount = getCoinAmount(200);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Try to distribute $500 when only $200 available
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount exceeds available funds");
        piePay.executeDUnitPayoutAmount(getCoinAmount(500));
    }

    function testBackwardCompatibilityPUnits() public {
        // Setup P-Units
        vm.prank(contributor1);
        piePay.submitContribution(300e18, "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(200e18, "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund with enough to pay all P-Units
        uint256 fundAmount = getCoinAmount(600);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Test that original function works the same as type(uint256).max
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // All P-Units should be cleared
        assertEq(piePay.pUnits(contributor1), 0, "All P-Units should be cleared");
        assertEq(piePay.pUnits(contributor2), 0, "All P-Units should be cleared");
        
        // All funds distributed
        uint256 totalReceived = coin.balanceOf(contributor1) + coin.balanceOf(contributor2);
        assertEq(totalReceived, getCoinAmount(500), "Should distribute exactly $500 (total P-Units)");
        
        // Should have $100 remaining since we only needed $500 for P-Units
        assertEq(piePay.payrollPool(), getCoinAmount(100), "Should have $100 remaining");
    }

    function testBackwardCompatibilityDUnits() public {
        // Setup D-Units
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 150e18, "Work 1");
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor2, 100e18, "Work 2");
        
        // Fund with more than needed
        uint256 fundAmount = getCoinAmount(400);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Test that original function works the same as type(uint256).max
        vm.prank(payrollManager);
        piePay.executeDUnitPayout();
        
        // All D-Units should be cleared
        assertEq(piePay.dUnits(contributor1), 0, "All D-Units should be cleared");
        assertEq(piePay.dUnits(contributor2), 0, "All D-Units should be cleared");
        
        // Should distribute exactly $250 (total D-Units)
        uint256 totalReceived = coin.balanceOf(contributor1) + coin.balanceOf(contributor2);
        assertEq(totalReceived, getCoinAmount(250), "Should distribute exactly $250 (total D-Units)");
        
        // Should have $150 remaining since we only needed $250 for D-Units
        assertEq(piePay.payrollPool(), getCoinAmount(150), "Should have $150 remaining");
    }

    function testMixedPayoutWorkflow() public {
        // Setup both P-Units and D-Units
        vm.prank(contributor1);
        piePay.submitContribution(300e18, "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor2, 200e18, "D-Unit work");
        
        // Fund with $1000
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Pay $150 of P-Units first (half)
        vm.prank(payrollManager);
        piePay.executePUnitPayoutAmount(getCoinAmount(150));
        
        assertEq(coin.balanceOf(contributor1), getCoinAmount(150), "Contributor1 gets $150 from P-Units");
        assertEq(piePay.pUnits(contributor1), 150e18, "Contributor1 has 150 P-Units remaining");
        assertEq(piePay.payrollPool(), getCoinAmount(850), "Should have $850 remaining");
        
        // Pay $100 of D-Units (half)
        vm.prank(payrollManager);
        piePay.executeDUnitPayoutAmount(getCoinAmount(100));
        
        assertEq(coin.balanceOf(contributor2), getCoinAmount(100), "Contributor2 gets $100 from D-Units");
        assertEq(piePay.dUnits(contributor2), 100e18, "Contributor2 has 100 D-Units remaining");
        assertEq(piePay.payrollPool(), getCoinAmount(750), "Should have $750 remaining");
        
        // Pay remaining P-Units with max value
        vm.prank(payrollManager);
        piePay.executePUnitPayoutAmount(type(uint256).max);
        
        assertEq(coin.balanceOf(contributor1), getCoinAmount(300), "Contributor1 should have total $300");
        assertEq(piePay.pUnits(contributor1), 0, "All P-Units should be cleared");
        assertEq(piePay.payrollPool(), getCoinAmount(600), "Should have $600 remaining");
    }



    function assertContribution(
        uint256 contributionId,
        string memory expectedDescription,
        PiePay.ContributionStatus expectedStatus,
        address expectedContributor,
        uint256 expectedPUnits
    ) internal {
        (address contributor, uint256 pUnitsClaimed, PiePay.ContributionStatus status, string memory description) = piePay.contributions(contributionId);
        
        assertEq(description, expectedDescription);
        assertEq(uint(status), uint(expectedStatus));
        assertEq(contributor, expectedContributor);
        assertEq(pUnitsClaimed, expectedPUnits);
    }





}

// Concrete test for USDC
contract PiePayUSDCTest is PiePayTest {
    function deployCoin() internal override returns (IMintableToken) {
        return IMintableToken(address(new MockUSDC()));
    }
    
    function getCoinAmount(uint256 baseAmount) internal pure override returns (uint256) {
        return baseAmount * 10**6; // USDC has 6 decimals
    }
}

// Concrete test for DAI
contract PiePayDAITest is PiePayTest {
    function deployCoin() internal override returns (IMintableToken) {
        return IMintableToken(address(new MockDAI()));
    }
    
    function getCoinAmount(uint256 baseAmount) internal pure override returns (uint256) {
        return baseAmount * 10**18; // DAI has 18 decimals
    }
}

