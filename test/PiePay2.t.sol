// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PiePay2.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockDAI.sol";
import "./mocks/IMintableToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract PiePayTest is Test {
    PiePay2 public piePay;
    IMintableToken public coin;
    
    address public owner;
    address public projectLead;
    address public payrollManager;
    address public contributor1;
    address public contributor2;
    address public equityManager;

    event PayrollFunded(uint256 amount);
    event UnitsGranted(PiePay.UnitType indexed unitType, address indexed recipient, uint256 amount, string reason, uint256 timestamp);
    event UnitsPurchased(PiePay.UnitType indexed unitType, address indexed purchaser, uint256 amount, uint256 cost, uint256 timestamp);
    event UnitsDistributed(PiePay.UnitType indexed unitType, uint256 totalUnitsProcessed, uint256 totalTokensDistributed, uint256 timestamp);

    function deployCoin() internal virtual returns (IMintableToken);
    function getCoinAmount(uint256 baseAmount) internal virtual returns (uint256);
    
    function setUp() public virtual {
        owner = address(this);
        projectLead = makeAddr("projectLead");
        payrollManager = makeAddr("payrollManager");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        equityManager = makeAddr("equityManager");

        // Deploy mock token
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
        );

        // Give payroll manager some tokens
        coin.mint(payrollManager, getCoinAmount(10000));
        coin.mint(equityManager, getCoinAmount(10000));
    }
    
    // ============ INITIAL SETUP TESTS ============
    
    function testInitialSetup() public {
        assertEq(piePay.projectName(), "Test Project");
        assertEq(piePay.projectDescription(), "A test project for PiePay");
        assertEq(piePay.projectLead(), projectLead);
        assertEq(piePay.payrollManager(), payrollManager);
        assertTrue(piePay.whitelistedContributors(contributor1));
        assertTrue(piePay.whitelistedContributors(contributor2));
        assertEq(piePay.getContributorCount(), 2);
    }
    
    function testInitialPermissions() public {
        // Check initial permissions are set correctly
        assertTrue(piePay.hasPermission(piePay.GRANT_P_UNITS(), projectLead));
        assertTrue(piePay.hasPermission(piePay.GRANT_D_UNITS(), payrollManager));
        assertTrue(piePay.hasPermission(piePay.GRANT_C_UNITS(), projectLead));
        assertTrue(piePay.hasPermission(piePay.DISTRIBUTE_UNITS(), payrollManager));
        assertTrue(piePay.hasPermission(piePay.MANAGE_PERMISSIONS(), projectLead));
        assertTrue(piePay.hasPermission(piePay.SET_C_UNIT_ALLOWANCE(), projectLead));
    }
    
    function testInitialUnitConfigs() public {
        // Check P-Unit config
        (uint256 pPrice, bool pConsumable, bool pPurchasable) = piePay.unitConfigs(PiePay.UnitType.P_UNITS);
        assertEq(pPrice, 0);
        assertTrue(pConsumable);
        assertFalse(pPurchasable);
        
        // Check D-Unit config
        (uint256 dPrice, bool dConsumable, bool dPurchasable) = piePay.unitConfigs(PiePay.UnitType.D_UNITS);
        assertEq(dPrice, getCoinAmount(1));
        assertTrue(dConsumable);
        assertTrue(dPurchasable);
        
        // Check C-Unit config
        (uint256 cPrice, bool cConsumable, bool cPurchasable) = piePay.unitConfigs(PiePay.UnitType.C_UNITS);
        assertEq(cPrice, getCoinAmount(5));
        assertFalse(cConsumable);
        assertTrue(cPurchasable);
    }
    
    // ============ PERMISSION SYSTEM TESTS ============
    
    function testGrantAndRevokePermissions() public {
        bytes32 testPermission = piePay.GRANT_D_UNITS();
        
        // Grant permission to contributor1
        vm.prank(projectLead);
        piePay.grantPermission(testPermission, contributor1);
        assertTrue(piePay.hasPermission(testPermission, contributor1));
        
        // Revoke permission
        vm.prank(projectLead);
        piePay.revokePermission(testPermission, contributor1);
        assertFalse(piePay.hasPermission(testPermission, contributor1));
    }
    
    function testOnlyManagerCanManagePermissions() public {
        vm.prank(contributor1);
        vm.expectRevert("Insufficient permission");
        piePay.grantPermission(piePay.GRANT_D_UNITS(), contributor2);
        
        vm.prank(payrollManager);
        vm.expectRevert("Insufficient permission");
        piePay.grantPermission(piePay.GRANT_D_UNITS(), contributor2);
    }
    
    // ============ CONTRIBUTION SYSTEM TESTS (Legacy) ============
    
    function testSubmitContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(500, "Implemented new feature");
        
        (address contributor, uint256 pUnitsClaimed, PiePay.ContributionStatus status, string memory description) = 
         piePay.contributions(1);
        assertEq(description, "Implemented new feature");
        assertEq(uint(status), uint(PiePay.ContributionStatus.Pending));
        assertEq(contributor, contributor1);
        assertEq(pUnitsClaimed, 500);
    }

    function testReviewContributionAccepted() public {
        vm.prank(contributor1);
        piePay.submitContribution(605, "Implemented new feature");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);

        (,uint256 pUnitsClaimed, PiePay.ContributionStatus status,) = piePay.contributions(1);
        assertEq(uint(status), uint(PiePay.ContributionStatus.Approved));
        assertEq(605, pUnitsClaimed);
        
        (uint256 pUnits, , ) = piePay.getContributorUnits(contributor1);
        assertEq(605, pUnits);
    }

    function testReviewContributionRejected() public {
        vm.prank(contributor1);
        piePay.submitContribution(800, "Implemented new feature");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, false);
        
        (,uint256 pUnitsClaimed, PiePay.ContributionStatus status, ) = piePay.contributions(1);
        assertEq(uint(status), uint(PiePay.ContributionStatus.Rejected));
        assertEq(pUnitsClaimed, 800);
        
        uint256 pUnits = piePay.pUnits(contributor1);
        assertEq(pUnits, 0);
    }
    
    // ============ GENERIC UNIT SYSTEM TESTS ============
    
    function testGrantUnitsBasic() public {
        // Grant P-Units
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work completed");
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 100e18);
        
        // Grant D-Units
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 50e18, "Unpaid overtime");
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor1), 50e18);
        
        // Grant C-Units
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor1, 25e18, "Equity grant");
        assertEq(piePay.getUnitBalance(PiePay.UnitType.C_UNITS, contributor1), 25e18);
    }
    
    function testGrantUnitsPermissions() public {
        // Test insufficient permissions
        vm.prank(contributor1);
        vm.expectRevert("Insufficient permission");
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 100e18, "Unauthorized");
        
        vm.prank(projectLead);
        vm.expectRevert("Insufficient permission");
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 50e18, "Wrong role");
    }
    
    function testGrantUnitsValidation() public {
        vm.prank(projectLead);
        vm.expectRevert("Amount must be greater than 0");
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 0, "Zero amount");
        
        vm.prank(projectLead);
        vm.expectRevert("Reason cannot be empty");
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "");
    }
    
    function testUnitHolderTracking() public {
        // Initially no holders
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 0);
        
        // Grant to contributor1
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work");
        
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 1);
        address[] memory holders = piePay.getUnitHolders(PiePay.UnitType.P_UNITS);
        assertEq(holders[0], contributor1);
        
        // Grant to contributor2
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 50e18, "More work");
        
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 2);
        holders = piePay.getUnitHolders(PiePay.UnitType.P_UNITS);
        // Note: order might vary, so check both are present
        assertTrue(holders[0] == contributor1 || holders[1] == contributor1);
        assertTrue(holders[0] == contributor2 || holders[1] == contributor2);
    }
    
    // ============ PURCHASE SYSTEM TESTS ============
    
    function testPurchaseDUnits() public {
        uint256 purchaseAmount = getCoinAmount(100);
        coin.mint(contributor1, purchaseAmount);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), purchaseAmount);
        
        vm.prank(contributor1);
        piePay.purchaseUnits(PiePay.UnitType.D_UNITS, 100e18);
        
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor1), 100e18);
        assertEq(piePay.payrollPool(), purchaseAmount);
    }
    
    function testPurchaseCUnitsWithAllowance() public {
        uint256 purchaseAmount = getCoinAmount(500); // 100 C-Units * $5 each
        coin.mint(contributor1, purchaseAmount);
        
        // Set allowance first
        vm.prank(projectLead);
        piePay.setCUnitPurchaseAllowance(contributor1, 100e18);
        
        // Grant purchase permission
        vm.prank(projectLead);
        piePay.grantPermission(piePay.PURCHASE_C_UNITS(), contributor1);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), purchaseAmount);
        
        vm.prank(contributor1);
        piePay.purchaseUnits(PiePay.UnitType.C_UNITS, 100e18);
        
        assertEq(piePay.getUnitBalance(PiePay.UnitType.C_UNITS, contributor1), 100e18);
        assertEq(piePay.cUnitPurchaseAllowance(contributor1), 0); // Allowance used up
    }
    
    function testPurchaseCUnitsWithoutPermission() public {
        vm.prank(contributor1);
        vm.expectRevert("Not authorized to purchase C-Units");
        piePay.purchaseUnits(PiePay.UnitType.C_UNITS, 100e18);
    }
    
    function testPurchaseCUnitsExceedsAllowance() public {
        vm.prank(projectLead);
        piePay.setCUnitPurchaseAllowance(contributor1, 50e18);
        
        vm.prank(projectLead);
        piePay.grantPermission(piePay.PURCHASE_C_UNITS(), contributor1);
        
        vm.prank(contributor1);
        vm.expectRevert("Exceeds purchase allowance");
        piePay.purchaseUnits(PiePay.UnitType.C_UNITS, 100e18);
    }
    
    function testPurchaseNonPurchasableUnit() public {
        vm.prank(contributor1);
        vm.expectRevert("Unit type not purchasable");
        piePay.purchaseUnits(PiePay.UnitType.P_UNITS, 100e18);
    }
    
    // ============ DISTRIBUTION SYSTEM TESTS ============
    
    function testDistributePUnitsBasic() public {
        // Setup P-Units
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 600e18, "Work 1");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 400e18, "Work 2");
        
        // Fund contract
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(1000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(1000));
        
        // Distribute
        vm.prank(payrollManager);
        piePay.distributePUnits();
        
        // Check distributions
        assertGe(coin.balanceOf(contributor1), getCoinAmount(600));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(400));
        
        // Check P-Units are consumed
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 0);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor2), 0);
    }
    
    function testDistributeDUnitsBasic() public {
        // Setup D-Units
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 600e18, "Debt 1");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor2, 400e18, "Debt 2");
        
        // Fund contract
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(500));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(500));
        
        // Distribute half
        vm.prank(payrollManager);
        piePay.distributeDUnits();
        
        // Check distributions (500 total, proportional)
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
        
        // Check D-Units are reduced but not zero
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor1), 300e18);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor2), 200e18);
    }
    
    function testDistributeCUnitsBasic() public {
        // Setup C-Units
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor1, 60e18, "Equity 1");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor2, 40e18, "Equity 2");
        
        // Fund contract
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(200));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(200));
        
        // Distribute
        vm.prank(payrollManager);
        piePay.distributeCUnits();
        
        // Check distributions
        assertGe(coin.balanceOf(contributor1), getCoinAmount(120));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(80));
        
        // Check C-Units are NOT consumed (permanent)
        assertEq(piePay.getUnitBalance(PiePay.UnitType.C_UNITS, contributor1), 60e18);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.C_UNITS, contributor2), 40e18);
    }
    
    function testDistributePartialAmount() public {
        // Setup P-Units
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 600e18, "Work");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 400e18, "Work");
        
        // Fund with more than needed
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(2000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(2000));
        
        // Distribute only $500
        vm.prank(payrollManager);
        piePay.distributePUnitsAmount(getCoinAmount(500));
        
        // Check partial distributions
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
        
        // Check P-Units are partially consumed
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 300e18);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor2), 200e18);
        
        // Check remaining funds
        assertEq(piePay.payrollPool(), getCoinAmount(1500));
    }
    
    function testWaterfallDistribution() public {
        // Setup all unit types
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 200e18, "P work");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 300e18, "D work");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor1, 100e18, "C equity");
        
        // Fund contract
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(1000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(1000));
        
        // Execute waterfall with limited amount
        vm.prank(payrollManager);
        piePay.distributeWaterfall(getCoinAmount(450));
        
        // P-Units should be fully paid (200), D-Units partially (250 out of 300)
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 0);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor1), 50e18);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.C_UNITS, contributor1), 100e18);
        
        assertEq(coin.balanceOf(contributor1), getCoinAmount(450));
        assertEq(piePay.payrollPool(), getCoinAmount(550));
    }
    
    // ============ REMOVAL BUG FIX TESTS ============
    
    function testRemovedContributorWithPUnitsStillReceivesPayment() public {
        // Setup P-Units for both contributors
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 600e18, "Work 1");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 400e18, "Work 2");
        
        // Remove contributor1 from whitelist
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        // Verify removal
        assertFalse(piePay.whitelistedContributors(contributor1));
        assertEq(piePay.getContributorCount(), 1);
        
        // But P-Units should remain
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 600e18);
        
        // Fund and distribute
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(500));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(500));
        
        vm.prank(payrollManager);
        piePay.distributePUnits();
        
        // Both should receive proportional payments
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
    }
    
    function testRemovedContributorWithDUnitsStillReceivesPayment() public {
        // Setup D-Units for both contributors
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 600e18, "Past work");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor2, 400e18, "Past work");
        
        // Remove contributor1
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        // Fund and distribute
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(500));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(500));
        
        vm.prank(payrollManager);
        piePay.distributeDUnits();
        
        // Both should receive payments (this was the bug that's now fixed)
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
        
        // Check D-Units are properly reduced
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor1), 300e18);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.D_UNITS, contributor2), 200e18);
    }
    
    function testAllUnitHoldersRemovedFromContributorList() public {
        // Grant units to both contributors
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 500e18, "Work");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor2, 300e18, "Work");
        
        // Remove both contributors
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        vm.prank(projectLead);
        piePay.removeContributor(contributor2);
        
        assertEq(piePay.getContributorCount(), 0);
        
        // Fund and distribute should still work
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(400));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(400));
        
        vm.prank(payrollManager);
        piePay.distributeDUnits();
        
        // Should still receive payments
        assertGe(coin.balanceOf(contributor1), getCoinAmount(250));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(150));
    }
    
    // ============ CLEANUP TESTS ============
    
    function testCleanupZeroBalanceHolders() public {
        // Grant units to create holders
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 200e18, "Work");
        
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 2);
        
        // Distribute all units (making balances zero)
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(300));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(300));
        
        vm.prank(payrollManager);
        piePay.distributePUnits();
        
        // Balances should be zero but holders list unchanged
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor1), 0);
        assertEq(piePay.getUnitBalance(PiePay.UnitType.P_UNITS, contributor2), 0);
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 2);
        
        // Cleanup should remove zero balance holders
        piePay.cleanupZeroBalanceHolders(PiePay.UnitType.P_UNITS);
        assertEq(piePay.getUnitHolderCount(PiePay.UnitType.P_UNITS), 0);
    }
    
    // ============ BACKWARD COMPATIBILITY TESTS ============
    
    function testLegacyFunctionsPUnits() public {
        // Setup using legacy contribution system
        vm.prank(contributor1);
        piePay.submitContribution(300e18, "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(200e18, "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(600));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(600));
        
        // Use legacy function
        vm.prank(payrollManager);
        piePay.executePUnitPayout();
        
        // Should work the same
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
        assertEq(piePay.pUnits(contributor1), 0);
        assertEq(piePay.pUnits(contributor2), 0);
    }
    
    function testLegacyFunctionsDUnits() public {
        // Use legacy grant function
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor1, 150e18, "Work 1");
        vm.prank(payrollManager);
        piePay.grantDUnits(contributor2, 100e18, "Work 2");
        
        // Fund
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(400));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(400));
        
        // Use legacy function
        vm.prank(payrollManager);
        piePay.executeDUnitPayout();
        
        // Should work the same
        assertGe(coin.balanceOf(contributor1), getCoinAmount(150));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(100));
        assertEq(piePay.dUnits(contributor1), 0);
        assertEq(piePay.dUnits(contributor2), 0);
    }
    
    function testLegacyPurchaseDUnitsWithMultiplier() public {
        uint256 paymentAmount = getCoinAmount(500);
        uint256 multiplier = 2;
        
        coin.mint(contributor1, paymentAmount);
        
        vm.prank(contributor1);
        coin.approve(address(piePay), paymentAmount);
        
        vm.prank(contributor1);
        piePay.purchaseDUnits(paymentAmount, multiplier);
        
        // Should grant correct amount of D-Units based on multiplier
        uint256 expectedDUnits = 1000e18; // $500 * 2 multiplier = 1000 D-Units
        assertEq(piePay.dUnits(contributor1), expectedDUnits);
        assertEq(piePay.payrollPool(), paymentAmount);
    }
    
    // ============ ERROR CONDITION TESTS ============
    
    function testDistributionErrorConditions() public {
        // No funds
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work");
        
        vm.prank(payrollManager);
        vm.expectRevert("No funds available");
        piePay.distributePUnits();
        
        // No unit holders
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(100));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(100));
        
        vm.prank(payrollManager);
        vm.expectRevert("No unit holders to distribute to");
        piePay.distributeDUnits();
    }
    
    function testDistributionPermissions() public {
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work");
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(100));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(100));
        
        vm.prank(contributor1);
        vm.expectRevert("Insufficient permission");
        piePay.distributePUnits();
        
        vm.prank(projectLead);
        vm.expectRevert("Insufficient permission");
        piePay.distributeDUnits();
    }
    
    function testDistributionAmountValidation() public {
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work");
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(100));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(100));
        
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount must be greater than 0");
        piePay.distributePUnitsAmount(0);
        
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount exceeds available funds");
        piePay.distributePUnitsAmount(getCoinAmount(200));
    }
    
    function testWaterfallValidation() public {
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(100));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(100));
        
        vm.prank(payrollManager);
        vm.expectRevert("Amount must be greater than 0");
        piePay.distributeWaterfall(0);
        
        vm.prank(payrollManager);
        vm.expectRevert("Amount exceeds available funds");
        piePay.distributeWaterfall(getCoinAmount(200));
    }
    
    // ============ VIEW FUNCTION TESTS ============
    
    function testGetTotalUnits() public {
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "Work 1");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor2, 200e18, "Work 2");
        
        assertEq(piePay.getTotalUnits(PiePay.UnitType.P_UNITS), 300e18);
        assertEq(piePay.getTotalUnits(PiePay.UnitType.D_UNITS), 0);
    }
    
    function testGetCurrentDistributionInfo() public {
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "P work");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 200e18, "D work");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor1, 50e18, "C equity");
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(1000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(1000));
        
        (uint256 totalP, uint256 totalD, uint256 totalC, uint256 funds) = piePay.getCurrentDistributionInfo();
        assertEq(totalP, 100e18);
        assertEq(totalD, 200e18);
        assertEq(totalC, 50e18);
        assertEq(funds, getCoinAmount(1000));
    }
    
    function testLegacyViewFunctions() public {
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.P_UNITS, contributor1, 100e18, "P work");
        vm.prank(payrollManager);
        piePay.grantUnits(PiePay.UnitType.D_UNITS, contributor1, 200e18, "D work");
        vm.prank(projectLead);
        piePay.grantUnits(PiePay.UnitType.C_UNITS, contributor1, 50e18, "C equity");
        
        assertEq(piePay.pUnits(contributor1), 100e18);
        assertEq(piePay.dUnits(contributor1), 200e18);
        assertEq(piePay.cUnits(contributor1), 50e18);
        
        (uint256 p, uint256 d, uint256 c) = piePay.getContributorUnits(contributor1);
        assertEq(p, 100e18);
        assertEq(d, 200e18);
        assertEq(c, 50e18);
    }
    
    // ============ ADMINISTRATIVE TESTS ============
    
    function testWithdrawFunds() public {
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(1000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(1000));
        
        uint256 initialBalance = coin.balanceOf(contributor1);
        
        vm.prank(payrollManager);
        piePay.withdrawFunds(contributor1, getCoinAmount(300));
        
        assertEq(coin.balanceOf(contributor1), initialBalance + getCoinAmount(300));
        assertEq(piePay.payrollPool(), getCoinAmount(700));
    }
    
    function testWithdrawFundsValidation() public {
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(100));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(100));
        
        vm.prank(payrollManager);
        vm.expectRevert("Amount must be greater than 0");
        piePay.withdrawFunds(contributor1, 0);
        
        vm.prank(payrollManager);
        vm.expectRevert("Insufficient funds");
        piePay.withdrawFunds(contributor1, getCoinAmount(200));
        
        vm.prank(payrollManager);
        vm.expectRevert("Invalid recipient");
        piePay.withdrawFunds(address(0), getCoinAmount(50));
    }
    
    // ============ HELPER FUNCTIONS ============
    
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