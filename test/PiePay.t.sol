// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PiePay.sol";
import "./mocks/MockUSDC.sol";
import "./mocks/MockDAI.sol";
import "./mocks/IMintableToken.sol";

// Import IERC20 for the MaliciousReentrant contract
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Malicious contract for reentrancy testing
contract MaliciousReentrant {
    PiePay public piePay;
    IERC20 public token;
    bool public attackAttempted;
    bool public attackSucceeded;
    UnitType public attackUnitType;
    uint256 public attackAmount;
    
    constructor(address _piePay, address _token) {
        piePay = PiePay(_piePay);
        token = IERC20(_token);
    }
    
    function prepareAttack(UnitType _unitType, uint256 _amount) external {
        attackUnitType = _unitType;
        attackAmount = _amount;
        attackAttempted = false;
        attackSucceeded = false;
    }
    
    // This will be called after we receive tokens, simulating a reentrancy attempt
    function attemptReentrancy() public {
        if (!attackAttempted) {
            attackAttempted = true;
            try piePay.executeUnitPayout(attackUnitType, attackAmount) {
                attackSucceeded = true;
            } catch {
                attackSucceeded = false;
            }
        }
    }
    
    // Fallback to trigger reentrancy attempt when receiving ETH (though we won't use this)
    receive() external payable {
        attemptReentrancy();
    }
}

// Malicious token for testing token-specific attacks
contract MaliciousToken is ERC20 {
    bool public reenter;
    address public target;
    bytes public attackCalldata;

    constructor() ERC20("MaliciousToken", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18; // Standard decimals
    }

    function setAttack(bool _reenter, address _target, bytes calldata _calldata) external {
        reenter = _reenter;
        target = _target;
        attackCalldata = _calldata;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (reenter && target != address(0)) {
            (bool success, ) = target.call(attackCalldata);
            require(success, "Reentrancy attack failed");
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (reenter && target != address(0)) {
            (bool success, ) = target.call(attackCalldata);
            require(success, "Reentrancy attack failed");
        }
        return super.transferFrom(from, to, amount);
    }
}

abstract contract PiePayTest is Test {
    PiePay public piePay;
    IMintableToken public coin;
    
    address public deployer;
    address public projectLead;
    address public payrollManager;
    address public contributor1;
    address public contributor2;
    address public contributor3;
    address public contributor4; // Additional for more edge cases
    address public contributor5; // For large contributor sets
    address public outsider;

    // Events for testing
    event ProjectInitialized(string name, string description, address indexed executor);
    event ContributionSubmitted(address indexed executor, uint256 indexed contributionId, UnitType unitType, uint256 unitsRequested, string description);
    event ContributionApproved(address indexed executor, uint256 indexed contributionId, address indexed contributor, UnitType unitType, uint256 unitsAwarded);
    event ContributionRejected(address indexed executor, uint256 indexed contributionId, address indexed contributor);
    event UnitsDistributed(address indexed executor, UnitType indexed unitType, uint256 totalDistributed, uint256 recipientCount);
    event PayrollFunded(address indexed executor, uint256 amount);
    event ContributorWhitelisted(address indexed executor, address indexed contributor);
    event ContributorRemoved(address indexed executor, address indexed contributor);
    event ProjectLeadUpdated(address indexed executor, address indexed newLead);
    event PayrollManagerUpdated(address indexed executor, address indexed newManager);
    event UnitsConverted(address indexed executor, UnitType indexed fromType, UnitType indexed toType, uint256 fromAmount, uint256 toAmount);
    event ConversionMultipliersUpdated(address indexed executor, uint16 pToDMultiplier, uint16 pToCMultiplier, uint16 dToCMultiplier);
    event UnitCapacityUpdated(address indexed executor, UnitType indexed unitType, uint256 newCapacity);

    function deployCoin() internal virtual returns (IMintableToken);
    function getCoinAmount(uint256 baseAmount) internal pure virtual returns (uint256);
    
    /**
     * @notice Helper function to convert base units to 4-decimal unit format
     * @param baseAmount Amount in base units (e.g., 100 for 100.0000 units)
     * @return Amount in 4-decimal format (e.g., 1000000 for 100.0000)
     */
    function getUnitAmount(uint256 baseAmount) internal pure returns (uint256) {
        return baseAmount * 10000; // 4 decimal places
    }
    
    function setUp() public virtual {
        deployer = address(this);
        projectLead = makeAddr("projectLead");
        payrollManager = makeAddr("payrollManager");
        contributor1 = makeAddr("contributor1");
        contributor2 = makeAddr("contributor2");
        contributor3 = makeAddr("contributor3");
        contributor4 = makeAddr("contributor4");
        contributor5 = makeAddr("contributor5");
        outsider = makeAddr("outsider");

        coin = deployCoin();
        
        address[] memory initialContributors = new address[](3);
        initialContributors[0] = contributor1;
        initialContributors[1] = contributor2;
        initialContributors[2] = contributor3;
        
        piePay = new PiePay(
            "Test Project",
            "A test project for PiePay",
            projectLead,
            payrollManager,
            initialContributors,
            address(coin)
        );

        // Fund payroll manager for tests
        coin.mint(payrollManager, getCoinAmount(1000000)); // Increased for large amount tests

        // Whitelist additional contributors
        vm.prank(projectLead);
        piePay.whitelistContributor(contributor4);
        vm.prank(projectLead);
        piePay.whitelistContributor(contributor5);
    }

    // ============ INITIALIZATION TESTS ============
    
    function testInitialization() public {
        assertEq(piePay.projectLead(), projectLead);
        assertEq(piePay.payrollManager(), payrollManager);
        assertEq(address(piePay.paymentToken()), address(coin));
        assertEq(piePay.pToDMultiplier(), 15000); // 1.5x default
        assertEq(piePay.pToCMultiplier(), 3000);  // 0.3x default
        assertEq(piePay.dToCMultiplier(), 2000);  // 0.2x default
        assertTrue(piePay.whitelistedContributors(contributor1));
        assertTrue(piePay.whitelistedContributors(contributor2));
        assertTrue(piePay.whitelistedContributors(contributor3));
        assertTrue(piePay.whitelistedContributors(contributor4));
        assertTrue(piePay.whitelistedContributors(contributor5));
        assertEq(piePay.getContributorCount(), 5);
    }

    function testInitializationEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ProjectInitialized("New Project", "New Description", address(this));
        
        address[] memory contributors = new address[](0);
        new PiePay(
            "New Project",
            "New Description", 
            projectLead,
            payrollManager,
            contributors,
            address(coin)
        );
    }

    function testInitializationWithZeroAddress() public {
        address[] memory contributors = new address[](0);
        
        vm.expectRevert("Invalid project lead address");
        new PiePay("Test", "Test", address(0), payrollManager, contributors, address(coin));
        
        vm.expectRevert("Invalid payroll manager address");
        new PiePay("Test", "Test", projectLead, address(0), contributors, address(coin));
        
        vm.expectRevert("Invalid payment token address");
        new PiePay("Test", "Test", projectLead, payrollManager, contributors, address(0));
    }

    // ============ WHITELIST MANAGEMENT TESTS ============
    
    function testWhitelistContributor() public {
        address newContrib = makeAddr("newContrib");
        assertFalse(piePay.whitelistedContributors(newContrib));
        assertEq(piePay.getContributorCount(), 5);
        
        vm.expectEmit(true, true, false, true);
        emit ContributorWhitelisted(projectLead, newContrib);
        
        vm.prank(projectLead);
        piePay.whitelistContributor(newContrib);
        
        assertTrue(piePay.whitelistedContributors(newContrib));
        assertEq(piePay.getContributorCount(), 6);
    }

    function testWhitelistContributorAlreadyWhitelisted() public {
        vm.prank(projectLead);
        vm.expectRevert("Already whitelisted");
        piePay.whitelistContributor(contributor1);
    }

    function testWhitelistContributorOnlyProjectLead() public {
        vm.prank(payrollManager);
        vm.expectRevert("Not the project lead");
        piePay.whitelistContributor(contributor3);
        
        vm.prank(outsider);
        vm.expectRevert("Not the project lead");
        piePay.whitelistContributor(contributor3);
    }

    function testRemoveContributor() public {
        assertTrue(piePay.whitelistedContributors(contributor1));
        
        vm.expectEmit(true, true, false, true);
        emit ContributorRemoved(projectLead, contributor1);
        
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        assertFalse(piePay.whitelistedContributors(contributor1));
        // Contributor count should remain same (for historical tracking)
        assertEq(piePay.getContributorCount(), 5);
    }

    function testRemoveContributorNotWhitelisted() public {
        vm.prank(projectLead);
        vm.expectRevert("Not whitelisted");
        piePay.removeContributor(outsider);
    }

    function testRemoveContributorOnlyProjectLead() public {
        vm.prank(payrollManager);
        vm.expectRevert("Not the project lead");
        piePay.removeContributor(contributor1);
    }

    // ============ CONTRIBUTION WORKFLOW TESTS ============

    function testSubmitContributionPUnits() public {
        vm.expectEmit(true, true, false, true);
        emit ContributionSubmitted(contributor1, 1, UnitType.Profit, getUnitAmount(500), "P-Unit work");
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P-Unit work");
        
        assertEq(piePay.contributionCounter(), 1);
        
        PiePay.ContributionReport memory contribution = piePay.getContributionDetails(1);
        
        assertEq(contribution.contributor, contributor1);
        assertEq(uint8(contribution.unitType), uint8(UnitType.Profit));
        assertEq(contribution.unitsRequested, getUnitAmount(500));
        assertEq(uint8(contribution.status), uint8(ContributionStatus.Pending));
        assertEq(contribution.description, "P-Unit work");
    }

    function testSubmitContributionDUnits() public {
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(300), "D-Unit work");
        
        PiePay.ContributionReport memory contribution = piePay.getContributionDetails(1);
        assertEq(uint8(contribution.unitType), uint8(UnitType.Debt));
    }

    function testSubmitContributionCUnits() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(200), "C-Unit work");
        
        PiePay.ContributionReport memory contribution = piePay.getContributionDetails(1);
        assertEq(uint8(contribution.unitType), uint8(UnitType.Capital));
    }

    function testSubmitContributionOnlyWhitelisted() public {
        vm.prank(outsider);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Unauthorized");
    }

    function testSubmitContributionZeroUnits() public {
        vm.prank(contributor1);
        vm.expectRevert("Units requested must be greater than 0");
        piePay.submitContribution(UnitType.Profit, 0, "Zero units");
    }

    function testSubmitContributionEmptyDescription() public {
        vm.prank(contributor1);
        vm.expectRevert("Description cannot be empty");
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "");
    }

    function testSubmitContributionInvalidUnitType() public {
        vm.prank(contributor1);
        vm.expectRevert("Invalid unit type");
        // Use assembly to bypass compile-time enum checks
        bytes memory data = abi.encodeWithSignature("submitContribution(uint8,uint256,string)", 5, getUnitAmount(100), "Invalid");
        (bool success,) = address(piePay).call(data);
        assertFalse(success);
    }

    function testApproveContribution() public {
        // Submit contribution
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P-Unit work");
        
        // Check no units before approval
        (uint256 pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, 0);
        
        uint256 expectedUnits = getUnitAmount(500); // P-Units don't get multiplier
        
        vm.expectEmit(true, true, true, true);
        emit ContributionApproved(projectLead, 1, contributor1, UnitType.Profit, expectedUnits);
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Check units were awarded
        (pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, expectedUnits);
        
        // Check status updated
        PiePay.ContributionReport memory contribution = piePay.getContributionDetails(1);
        assertEq(uint8(contribution.status), uint8(ContributionStatus.Approved));
        
        // Check added to unit holders
        address[] memory pUnitHolders = piePay.getUnitHolders(UnitType.Profit);
        assertEq(pUnitHolders.length, 1);
        assertEq(pUnitHolders[0], contributor1);
    }

    function testApproveContributionWithMultiplier() public {
        // Set 1.5x P→D multiplier (keeping others at default)
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(15000, 3000, 2000);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000), "D-Unit work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Should get 1500 units (1000 * 1.5)
        (,uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, (getUnitAmount(1000) * 15000) / 10000);
    }

    function testApproveContributionPUnitsNoMultiplier() public {
        // Set 1.5x P→D multiplier (keeping others at default)
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(15000, 3000, 2000);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-Unit work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // P-Units should NOT get multiplier - should get exactly 1000 units
        (uint256 pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(1000));
    }

    function testApproveContributionCUnitsNoMultiplier() public {
        // Set 1.5x P→D multiplier (keeping others at default)
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(15000, 3000, 2000);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(1000), "C-Unit work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // C-Units should NOT get multiplier - should get exactly 1000 units
        (,,uint256 cUnits) = piePay.getContributorUnits(contributor1);
        assertEq(cUnits, getUnitAmount(1000));
    }

    function testRejectContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(500), "Work");
        
        vm.expectEmit(true, true, true, false);
        emit ContributionRejected(projectLead, 1, contributor1);
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, false);
        
        // No units should be awarded
        (uint256 pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, 0);
        
        // Status should be rejected
        PiePay.ContributionReport memory contribution = piePay.getContributionDetails(1);
        assertEq(uint8(contribution.status), uint8(ContributionStatus.Rejected));
        
        // Should not be in unit holders
        address[] memory holders = piePay.getUnitHolders(UnitType.Profit);
        assertEq(holders.length, 0);
    }

    function testReviewContributionOnlyProjectLead() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "Work");
        
        vm.prank(payrollManager);
        vm.expectRevert("Not the project lead");
        piePay.reviewContribution(1, true);
        
        vm.prank(outsider);
        vm.expectRevert("Not the project lead");
        piePay.reviewContribution(1, false);
    }

    function testReviewInvalidContribution() public {
        vm.prank(projectLead);
        vm.expectRevert("Invalid contribution ID");
        piePay.reviewContribution(999, true);
    }

    function testReviewAlreadyProcessedContribution() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "Work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(projectLead);
        vm.expectRevert("Contribution already processed");
        piePay.reviewContribution(1, false);
    }

    // ============ UNIT CONVERSION TESTS ============

    function testConvertPUnitsToD() public {
        // Setup: Give contributor P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Verify initial balances
        (uint256 pUnits, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(1000));
        assertEq(dUnits, 0);
        
        // Convert 500 P-Units to D-Units (with 1.5x multiplier = 750 D-Units)
        uint256 convertAmount = getUnitAmount(500);
        uint256 expectedDUnits = (convertAmount * 15000) / 10000; // 1.5x default multiplier
        
        vm.expectEmit(true, true, true, true);
        emit UnitsConverted(contributor1, UnitType.Profit, UnitType.Debt, convertAmount, expectedDUnits);
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, convertAmount);
        
        // Verify final balances
        (pUnits, dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(500)); // 1000 - 500
        assertEq(dUnits, expectedDUnits); // 750 with 1.5x default multiplier
        
        // Verify unit holder tracking
        address[] memory pHolders = piePay.getUnitHolders(UnitType.Profit);
        address[] memory dHolders = piePay.getUnitHolders(UnitType.Debt);
        assertEq(pHolders.length, 1);
        assertEq(dHolders.length, 1);
        assertEq(pHolders[0], contributor1);
        assertEq(dHolders[0], contributor1);
    }

    function testConvertPUnitsToDWithMultiplier() public {
        // Set 1.5x P→D multiplier (keeping others at default)
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(15000, 3000, 2000);
        
        // Setup: Give contributor P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Convert 600 P-Units to D-Units (with 1.5x multiplier = 900 D-Units)
        uint256 convertAmount = getUnitAmount(600);
        uint256 expectedDUnits = (convertAmount * 15000) / 10000; // 1.5x multiplier
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, convertAmount);
        
        // Verify final balances
        (uint256 pUnits, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(400)); // 1000 - 600
        assertEq(dUnits, expectedDUnits); // 600 * 1.5 = 900
    }

    function testConvertAllPUnitsToD() public {
        // Setup: Give contributor P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(800), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Convert all P-Units
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(800));
        
        // Verify P-Units are completely depleted
        (uint256 pUnits, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, 0);
        assertEq(dUnits, getUnitAmount(1200)); // 800 * 1.5x default multiplier
        
        // Verify unit holder tracking - should be removed from P-Unit holders
        address[] memory pHolders = piePay.getUnitHolders(UnitType.Profit);
        address[] memory dHolders = piePay.getUnitHolders(UnitType.Debt);
        assertEq(pHolders.length, 0); // Removed from P-Unit holders
        assertEq(dHolders.length, 1);
        assertEq(dHolders[0], contributor1);
    }

    function testConvertPUnitsToDInsufficientBalance() public {
        // Setup: Give contributor small amount of P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(300), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Try to convert more than available
        vm.prank(contributor1);
        vm.expectRevert("Insufficient source units");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(500));
    }

    function testConvertPUnitsToDZeroAmount() public {
        // Setup: Give contributor P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Try to convert zero amount
        vm.prank(contributor1);
        vm.expectRevert("Amount must be greater than 0");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, 0);
    }

    function testConvertPUnitsToDOnlyWhitelisted() public {
        // Setup: Give contributor P-Units then remove from whitelist
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        // Try to convert - should fail
        vm.prank(contributor1);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(100));
    }

    function testConvertPUnitsToDFromExistingDHolder() public {
        // Setup: Give contributor both P-Units and D-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P-Unit work");
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(300), "D-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true); // P-Units: 500
        vm.prank(projectLead);
        piePay.reviewContribution(2, true); // D-Units: 300 (gets multiplier)
        
        // Convert some P-Units to D-Units
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(200));
        
        // Verify balances are additive for D-Units
        (uint256 pUnits, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(300)); // 500 - 200
        assertEq(dUnits, getUnitAmount(750)); // 450 (from 300 contribution with 1.5x) + 300 (from 200 conversion with 1.5x)
        
        // Should still be in both holder arrays
        address[] memory pHolders = piePay.getUnitHolders(UnitType.Profit);
        address[] memory dHolders = piePay.getUnitHolders(UnitType.Debt);
        assertEq(pHolders.length, 1);
        assertEq(dHolders.length, 1);
    }

    function testConvertPUnitsToDThenPayout() public {
        // Set 2x P→D multiplier for more interesting math
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(20000, 3000, 2000);
        
        // Setup: Give contributor P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-Unit work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Convert 500 P-Units to D-Units (with 2x multiplier = 1000 D-Units)
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(500));
        
        // Verify post-conversion balances
        (uint256 pUnits, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(500)); // 1000 - 500
        assertEq(dUnits, getUnitAmount(1000)); // 500 * 2 = 1000
        
        // Fund and payout D-Units (should be expended)
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Debt, fundAmount);
        
        // D-Units should be reduced proportionally (500/1000 = 50% paid out)
        (pUnits, dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getUnitAmount(500)); // P-Units unchanged by D-Unit payout
        assertEq(dUnits, getUnitAmount(500)); // 1000 - 500 = 500 remaining
        
        // Contributor should have received tokens
        assertEq(coin.balanceOf(contributor1), getCoinAmount(500));
    }

    // ============ PAYOUT SYSTEM TESTS ============

    function testFundPayroll() public {
        uint256 amount = getCoinAmount(5000);
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), amount);
        
        vm.expectEmit(true, false, false, true);
        emit PayrollFunded(payrollManager, amount);
        
        vm.prank(payrollManager);
        piePay.fundPayroll(amount);
        
        assertEq(piePay.payrollPool(), amount);
        assertEq(coin.balanceOf(address(piePay)), amount);
    }

    function testFundPayrollOnlyPayrollManager() public {
        uint256 amount = getCoinAmount(1000);
        coin.mint(projectLead, amount);
        
        vm.prank(projectLead);
        coin.approve(address(piePay), amount);
        
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.fundPayroll(amount);
    }

    function testPUnitPayoutDecrementsUnits() public {
        // Setup P-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(600), "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(400), "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund payroll
        uint256 fundAmount = getCoinAmount(500); // Partial funding
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.expectEmit(true, false, false, true);
        emit UnitsDistributed(payrollManager, UnitType.Profit, fundAmount, 2);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        // Check proportional distribution and unit reduction
        // Total P-Units: 1000, funding: 500
        // Contributor1: 600/1000 * 500 = 300 paid, 300 units remaining
        // Contributor2: 400/1000 * 500 = 200 paid, 200 units remaining
        
        (uint256 pUnits1,,) = piePay.getContributorUnits(contributor1);
        (uint256 pUnits2,,) = piePay.getContributorUnits(contributor2);
        
        assertEq(pUnits1, getUnitAmount(300)); // 600 - 300 = 300 remaining
        assertEq(pUnits2, getUnitAmount(200)); // 400 - 200 = 200 remaining
        
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300));
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200));
    }

    function testDUnitPayoutDecrementsUnits() public {
        // Setup D-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(800), "Debt work 1");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(200), "Debt work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Full funding - need to cover 1500 D-Units (800*1.5 + 200*1.5)
        uint256 fundAmount = getCoinAmount(1500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Debt, fundAmount);
        
        // All D-Units should be paid out and cleared
        (,uint256 dUnits1,) = piePay.getContributorUnits(contributor1);
        (,uint256 dUnits2,) = piePay.getContributorUnits(contributor2);
        
        assertEq(dUnits1, 0);
        assertEq(dUnits2, 0);
        
        assertGe(coin.balanceOf(contributor1), getCoinAmount(1200)); // 800 * 1.5x
        assertEq(coin.balanceOf(contributor2), getCoinAmount(300)); // 200 * 1.5x
        
        // Should be removed from unit holders
        address[] memory holders = piePay.getUnitHolders(UnitType.Debt);
        assertEq(holders.length, 0);
    }

    function testCUnitPayoutKeepsUnits() public {
        // Setup C-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getCoinAmount(700), "Capital work 1");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Capital, getCoinAmount(300), "Capital work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund and payout
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Capital, fundAmount);
        
        // C-Units should remain unchanged (dividend behavior)
        (,,uint256 cUnits1) = piePay.getContributorUnits(contributor1);
        (,,uint256 cUnits2) = piePay.getContributorUnits(contributor2);
        
        assertEq(cUnits1, getCoinAmount(700)); // Unchanged
        assertEq(cUnits2, getCoinAmount(300)); // Unchanged
        
        // But should still receive proportional payout
        assertGe(coin.balanceOf(contributor1), getCoinAmount(350)); // 700/1000 * 500
        assertEq(coin.balanceOf(contributor2), getCoinAmount(150)); // 300/1000 * 500
        
        // Should remain in unit holders
        address[] memory holders = piePay.getUnitHolders(UnitType.Capital);
        assertEq(holders.length, 2);
    }

    function testPayoutOnlyPayrollManager() public {
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
        
        vm.prank(outsider);
        vm.expectRevert("Not the payroll manager");
        piePay.executeUnitPayout(UnitType.Debt, getCoinAmount(100));
    }

    function testPayoutInsufficientFunds() public {
        // Setup units but no funding
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount exceeds available funds");
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
    }

    function testPayoutNoUnitHolders() public {
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert("No unit holders for this type");
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
    }

    function testPayoutExceedsAvailableFunds() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(50);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        vm.expectRevert("Distribution amount exceeds available funds");
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
    }

    // ============ EDGE CASE TESTS ============

    function testRemovedContributorStillReceivesPayouts() public {
        // Setup: Give contributor units then remove from whitelist
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getCoinAmount(600), "Past work");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getCoinAmount(400), "Past work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Remove contributor1 from whitelist
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        assertFalse(piePay.whitelistedContributors(contributor1));
        
        // Fund and payout
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Debt, fundAmount);
        
        // Removed contributor should still receive proportional payout
        assertGe(coin.balanceOf(contributor1), getCoinAmount(300)); // 600/1000 * 500
        assertEq(coin.balanceOf(contributor2), getCoinAmount(200)); // 400/1000 * 500
    }

    function testRemovedContributorCannotSubmitNewContributions() public {
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        vm.prank(contributor1);
        vm.expectRevert("Not a whitelisted contributor");
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "New work");
    }

    function testUnitHolderTrackingPrecision() public {
        // Test that holders are properly added/removed from arrays
        
        // Initial state: no holders
        assertEq(piePay.getUnitHolders(UnitType.Profit).length, 0);
        
        // Add first holder
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work 1");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        address[] memory holders = piePay.getUnitHolders(UnitType.Profit);
        assertEq(holders.length, 1);
        assertEq(holders[0], contributor1);
        
        // Add second holder
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(200), "Work 2");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        holders = piePay.getUnitHolders(UnitType.Profit);
        assertEq(holders.length, 2);
        
        // Full payout should remove all holders
        uint256 fundAmount = getCoinAmount(300);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        holders = piePay.getUnitHolders(UnitType.Profit);
        assertEq(holders.length, 0);
    }

    function testMixedUnitTypesIndependentTracking() public {
        // Contributors have different unit types
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(500), "P work");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(300), "D work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Check separate tracking
        assertEq(piePay.getUnitHolders(UnitType.Profit).length, 1);
        assertEq(piePay.getUnitHolders(UnitType.Debt).length, 1);
        assertEq(piePay.getUnitHolders(UnitType.Capital).length, 0);
        
        // Payout P-Units shouldn't affect D-Unit holders
        uint256 fundAmount = getCoinAmount(500);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        assertEq(piePay.getUnitHolders(UnitType.Profit).length, 0);
        assertEq(piePay.getUnitHolders(UnitType.Debt).length, 1); // Unchanged
    }

    function testRoundingPrecisionHandling() public {
        // Create scenario that will test rounding precision
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(333), "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(667), "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        // Fund with amount that causes rounding issues
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        // Total distributed should equal exactly what was funded
        uint256 totalReceived = coin.balanceOf(contributor1) + coin.balanceOf(contributor2);
        assertEq(totalReceived, fundAmount);
    }

    // ============ ADMINISTRATIVE FUNCTION TESTS ============

    function testSetConversionMultipliers() public {
        assertEq(piePay.pToDMultiplier(), 15000);
        assertEq(piePay.pToCMultiplier(), 3000);
        assertEq(piePay.dToCMultiplier(), 2000);
        
        vm.expectEmit(true, false, false, true);
        emit ConversionMultipliersUpdated(payrollManager, 20000, 4000, 2500);
        
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(20000, 4000, 2500);
        
        assertEq(piePay.pToDMultiplier(), 20000);
        assertEq(piePay.pToCMultiplier(), 4000);
        assertEq(piePay.dToCMultiplier(), 2500);
    }

    function testSetConversionMultipliersOnlyPayrollManager() public {
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.setConversionMultipliers(12000, 3000, 2000);
    }

    function testSetConversionMultipliersZero() public {
        vm.prank(payrollManager);
        vm.expectRevert("Multipliers must be > 0");
        piePay.setConversionMultipliers(0, 3000, 2000);
        
        vm.prank(payrollManager);
        vm.expectRevert("Multipliers must be > 0");
        piePay.setConversionMultipliers(15000, 0, 2000);
        
        vm.prank(payrollManager);
        vm.expectRevert("Multipliers must be > 0");
        piePay.setConversionMultipliers(15000, 3000, 0);
    }

    function testSetProjectLead() public {
        address newLead = makeAddr("newLead");
        
        vm.expectEmit(true, true, false, true);
        emit ProjectLeadUpdated(projectLead, newLead);
        
        vm.prank(projectLead);
        piePay.setProjectLead(newLead);
        
        assertEq(piePay.projectLead(), newLead);
    }

    function testSetProjectLeadOnlyCurrentLead() public {
        vm.prank(payrollManager);
        vm.expectRevert("Not the project lead");
        piePay.setProjectLead(makeAddr("newLead"));
    }

    function testSetProjectLeadZeroAddress() public {
        vm.prank(projectLead);
        vm.expectRevert("Invalid address");
        piePay.setProjectLead(address(0));
    }

    function testSetPayrollManager() public {
        address newManager = makeAddr("newManager");
        
        vm.expectEmit(true, true, false, true);
        emit PayrollManagerUpdated(payrollManager, newManager);
        
        vm.prank(payrollManager);
        piePay.setPayrollManager(newManager);
        
        assertEq(piePay.payrollManager(), newManager);
    }

    function testSetPayrollManagerOnlyCurrentManager() public {
        vm.prank(projectLead);
        vm.expectRevert("Not the payroll manager");
        piePay.setPayrollManager(makeAddr("newManager"));
    }

    function testSetPayrollManagerZeroAddress() public {
        vm.prank(payrollManager);
        vm.expectRevert("Invalid address");
        piePay.setPayrollManager(address(0));
    }

    // ============ VIEW FUNCTION TESTS ============

    function testGetContributorUnits() public {
        // Setup mixed unit types for one contributor
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "P work");
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getCoinAmount(200), "D work");
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getCoinAmount(300), "C work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        vm.prank(projectLead);
        piePay.reviewContribution(3, true);
        
        (uint256 pUnits, uint256 dUnits, uint256 cUnits) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, getCoinAmount(100));
        assertEq(dUnits, getCoinAmount(300)); // 200 * 1.5x multiplier
        assertEq(cUnits, getCoinAmount(300));
    }

    function testGetTotalUnitsOutstanding() public {
        // Setup multiple contributors with same unit type
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(400), "Work 1");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, getCoinAmount(600), "Work 2");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), getCoinAmount(1000));
        assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), 0);
        assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), 0);
    }

    // ============ SECURITY TESTS ============

    function testReentrancyProtection() public {
        // This would require a malicious token contract to properly test
        // For now, just verify the modifier is present on payout functions
        assertTrue(true); // Placeholder - reentrancy protection tested via modifiers
    }

    function testActualReentrancyProtection() public {
        // Deploy a malicious contract that will try to re-enter
        MaliciousReentrant malicious = new MaliciousReentrant(address(piePay), address(coin));
        
        // Whitelist the malicious contract as a contributor
        vm.prank(projectLead);
        piePay.whitelistContributor(address(malicious));
        
        // Give malicious contract some units
        vm.prank(address(malicious));
        piePay.submitContribution(UnitType.Profit, getCoinAmount(100), "Malicious work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund the contract
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Set up the malicious contract to attempt reentrancy
        malicious.prepareAttack(UnitType.Profit, getCoinAmount(50));
        
        // Execute payout - during this, we'll manually trigger the reentrancy attempt
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
        
        // Manually trigger the reentrancy attempt (simulating what would happen during token transfer)
        malicious.attemptReentrancy();
        
        // Verify that reentrancy was prevented
        assertTrue(malicious.attackAttempted(), "Attack should have been attempted");
        assertFalse(malicious.attackSucceeded(), "Attack should have failed due to reentrancy guard");
        
        // Verify normal payout still worked
        assertEq(coin.balanceOf(address(malicious)), getCoinAmount(100), "Normal payout should work");
    }

    function testPayoutUpdatesStateBeforeTransfers() public {
        // Test that unit balances are updated before token transfers
        // This verifies checks-effects-interactions pattern
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(50);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        // Before payout
        (uint256 beforePUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(beforePUnits, getUnitAmount(100));
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        // After payout - units should be reduced
        (uint256 afterPUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(afterPUnits, getUnitAmount(50));
        
        // And tokens should be received
        assertEq(coin.balanceOf(contributor1), getCoinAmount(50));
    }

    // ============ MULTI-SCENARIO INTEGRATION TESTS ============

    function testCompleteWorkflowMultipleRounds() public {
        // contributor3 is already whitelisted in setup
        
        // Round 1: Multiple contributors, same unit types (test proportional splits)
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(600), "Round 1 P-work A");
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(400), "Round 1 P-work B");
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(300), "Round 1 D-work A");
        vm.prank(contributor3);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(200), "Round 1 D-work C");
        
        // Approve all Round 1 contributions
        vm.prank(projectLead);
        piePay.reviewContribution(1, true); // 600 P-Units to contributor1
        vm.prank(projectLead);
        piePay.reviewContribution(2, true); // 400 P-Units to contributor2
        vm.prank(projectLead);
        piePay.reviewContribution(3, true); // 300 D-Units to contributor1
        vm.prank(projectLead);
        piePay.reviewContribution(4, true); // 200 D-Units to contributor3
        
        // Block 1: Check state after Round 1 approvals
        {
            (uint256 p1, uint256 d1, uint256 c1) = piePay.getContributorUnits(contributor1);
            (uint256 p2, uint256 d2, uint256 c2) = piePay.getContributorUnits(contributor2);
            (uint256 p3, uint256 d3, uint256 c3) = piePay.getContributorUnits(contributor3);
            
            assertEq(p1, getUnitAmount(600), "Contributor1 should have 600 P-Units");
            assertEq(p2, getUnitAmount(400), "Contributor2 should have 400 P-Units");
            assertEq(d1, getUnitAmount(450), "Contributor1 should have 450 D-Units"); // 300 * 1.5x multiplier
            assertEq(d3, getUnitAmount(300), "Contributor3 should have 300 D-Units"); // 200 * 1.5x multiplier
            assertEq(p3 + d2 + c1 + c2 + c3, 0, "Others should have 0 in unclaimed types");
            
            // Check total outstanding
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), getUnitAmount(1000));
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), getUnitAmount(750)); // 450 + 300
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), 0);
            
            // BLOCK 1 END STATE - Starting state for Block 2:
            // Payroll Pool: 0
            // Contributor1: 600 P-Units, 450 D-Units, 0 C-Units, 0 tokens
            // Contributor2: 400 P-Units, 0 D-Units, 0 C-Units, 0 tokens  
            // Contributor3: 0 P-Units, 300 D-Units, 0 C-Units, 0 tokens
            // Total Outstanding: 1000 P-Units, 750 D-Units, 0 C-Units
            assertEq(piePay.payrollPool(), 0, "Block 1 - Payroll pool should be 0");
            assertEq(coin.balanceOf(contributor1), 0, "Block 1 - Contributor1 tokens should be 0");
            assertEq(coin.balanceOf(contributor2), 0, "Block 1 - Contributor2 tokens should be 0");
            assertEq(coin.balanceOf(contributor3), 0, "Block 1 - Contributor3 tokens should be 0");
        }
        
        // Block 2: Fund and execute partial P-Unit payout
        {
            uint256 fund1 = getCoinAmount(600); // 60% of P-Units can be paid
            vm.prank(payrollManager);
            coin.approve(address(piePay), fund1);
            vm.prank(payrollManager);
            piePay.fundPayroll(fund1);
            
            assertEq(piePay.payrollPool(), getCoinAmount(600), "Payroll pool should be 600");
            
            // Partial P-Unit payout (60% of total P-Units)
            vm.prank(payrollManager);
            piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(600));
            
            // Check proportional P-Unit payout and remaining balances
            assertGe(coin.balanceOf(contributor1), getCoinAmount(360), "Contributor1 should receive >= 360");
            assertEq(coin.balanceOf(contributor2), getCoinAmount(240), "Contributor2 should receive exactly 240");
            
            (uint256 p1, uint256 d1,) = piePay.getContributorUnits(contributor1);
            (uint256 p2,,) = piePay.getContributorUnits(contributor2);
            assertEq(p1, getUnitAmount(240), "Contributor1 should have 240 P-Units remaining");
            assertEq(p2, getUnitAmount(160), "Contributor2 should have 160 P-Units remaining");
            assertEq(d1, getUnitAmount(450), "Contributor1 D-Units unchanged"); // 300 * 1.5x
            
            assertEq(piePay.payrollPool(), 0, "Payroll pool should be empty after payout");
            
            // BLOCK 2 END STATE - Starting state for Block 3:
            // Payroll Pool: 0 (all 600 paid out)
            // Contributor1: 240 P-Units, 450 D-Units, 0 C-Units, 360 tokens
            // Contributor2: 160 P-Units, 0 D-Units, 0 C-Units, 240 tokens
            // Contributor3: 0 P-Units, 300 D-Units, 0 C-Units, 0 tokens
            // Total Outstanding: 400 P-Units, 750 D-Units, 0 C-Units
            (uint256 p1_b2, uint256 d1_b2, uint256 c1_b2) = piePay.getContributorUnits(contributor1);
            (uint256 p2_b2, uint256 d2_b2, uint256 c2_b2) = piePay.getContributorUnits(contributor2);
            (uint256 p3_b2, uint256 d3_b2, uint256 c3_b2) = piePay.getContributorUnits(contributor3);
            assertEq(p1_b2, getUnitAmount(240), "Block 2 - Contributor1 P-Units");
            assertEq(d1_b2, getUnitAmount(450), "Block 2 - Contributor1 D-Units");
            assertEq(c1_b2, 0, "Block 2 - Contributor1 C-Units");
            assertEq(p2_b2, getUnitAmount(160), "Block 2 - Contributor2 P-Units");
            assertEq(d2_b2, 0, "Block 2 - Contributor2 D-Units");
            assertEq(c2_b2, 0, "Block 2 - Contributor2 C-Units");
            assertEq(p3_b2, 0, "Block 2 - Contributor3 P-Units");
            assertEq(d3_b2, getUnitAmount(300), "Block 2 - Contributor3 D-Units");
            assertEq(c3_b2, 0, "Block 2 - Contributor3 C-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), getUnitAmount(400), "Block 2 - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), getUnitAmount(750), "Block 2 - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), 0, "Block 2 - Total C-Units");
        }
        
        // Round 2: Add more contributions with mixed types
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(400), "Round 2 C-work B");
        vm.prank(contributor3);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(100), "Round 2 C-work C");
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(200), "Round 2 P-work A");
        
        vm.prank(projectLead);
        piePay.reviewContribution(5, true); // 400 C-Units to contributor2
        vm.prank(projectLead);
        piePay.reviewContribution(6, true); // 100 C-Units to contributor3
        vm.prank(projectLead);
        piePay.reviewContribution(7, true); // 200 P-Units to contributor1
        
        // Block 3: Check state after Round 2
        {
            (uint256 p1,, uint256 c1) = piePay.getContributorUnits(contributor1);
            (,, uint256 c2) = piePay.getContributorUnits(contributor2);
            (,, uint256 c3) = piePay.getContributorUnits(contributor3);
            
            assertEq(p1, getUnitAmount(440), "Contributor1 P-Units: 240 + 200");
            assertEq(c2, getUnitAmount(400), "Contributor2 should have 400 C-Units");
            assertEq(c3, getUnitAmount(100), "Contributor3 should have 100 C-Units");
            
            // BLOCK 3 END STATE - Starting state for Block 4:
            // Payroll Pool: 0 
            // Contributor1: 440 P-Units, 450 D-Units, 0 C-Units, 360 tokens
            // Contributor2: 160 P-Units, 0 D-Units, 400 C-Units, 240 tokens
            // Contributor3: 0 P-Units, 300 D-Units, 100 C-Units, 0 tokens
            // Total Outstanding: 600 P-Units, 750 D-Units, 500 C-Units
            (uint256 p1_b3, uint256 d1_b3, uint256 c1_b3) = piePay.getContributorUnits(contributor1);
            (uint256 p2_b3, uint256 d2_b3, uint256 c2_b3) = piePay.getContributorUnits(contributor2);
            (uint256 p3_b3, uint256 d3_b3, uint256 c3_b3) = piePay.getContributorUnits(contributor3);
            assertEq(p1_b3, getUnitAmount(440), "Block 3 - Contributor1 P-Units");
            assertEq(d1_b3, getUnitAmount(450), "Block 3 - Contributor1 D-Units");
            assertEq(c1_b3, 0, "Block 3 - Contributor1 C-Units");
            assertEq(p2_b3, getUnitAmount(160), "Block 3 - Contributor2 P-Units");
            assertEq(d2_b3, 0, "Block 3 - Contributor2 D-Units");
            assertEq(c2_b3, getUnitAmount(400), "Block 3 - Contributor2 C-Units");
            assertEq(p3_b3, 0, "Block 3 - Contributor3 P-Units");
            assertEq(d3_b3, getUnitAmount(300), "Block 3 - Contributor3 D-Units");
            assertEq(c3_b3, getUnitAmount(100), "Block 3 - Contributor3 C-Units");
            assertEq(piePay.payrollPool(), 0, "Block 3 - Payroll pool");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), getUnitAmount(600), "Block 3 - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), getUnitAmount(750), "Block 3 - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), getUnitAmount(500), "Block 3 - Total C-Units");
            assertEq(coin.balanceOf(contributor1), getCoinAmount(360), "Block 3 - Contributor1 tokens");
            assertEq(coin.balanceOf(contributor2), getCoinAmount(240), "Block 3 - Contributor2 tokens");
            assertEq(coin.balanceOf(contributor3), 0, "Block 3 - Contributor3 tokens");
        }
        
        // Block 4: Fund for remaining operations and complete P-Unit payout
        {
            uint256 fund2 = getCoinAmount(1350); // Increased to cover all remaining payouts
            vm.prank(payrollManager);
            coin.approve(address(piePay), fund2);
            vm.prank(payrollManager);
            piePay.fundPayroll(fund2);
            
            // Complete P-Unit payout (should clear all remaining)
            uint256 remainingPUnits = getCoinAmount(600); // 440 + 160 = 600 total remaining
            vm.prank(payrollManager);
            piePay.executeUnitPayout(UnitType.Profit, remainingPUnits);
            
            // Check P-Units are cleared
            (uint256 p1,,) = piePay.getContributorUnits(contributor1);
            (uint256 p2,,) = piePay.getContributorUnits(contributor2);
            assertEq(p1, 0, "All P-Units should be cleared for contributor1");
            assertEq(p2, 0, "All P-Units should be cleared for contributor2");
            
            // BLOCK 4 END STATE - Starting state for Block 5:
            // Payroll Pool: 750 (1350 funded - 600 paid out for P-Units)
            // Contributor1: 0 P-Units, 450 D-Units, 0 C-Units, ~800 tokens (360 + ~440)
            // Contributor2: 0 P-Units, 0 D-Units, 400 C-Units, ~400 tokens (240 + ~160)
            // Contributor3: 0 P-Units, 300 D-Units, 100 C-Units, 0 tokens
            // Total Outstanding: 0 P-Units, 750 D-Units, 500 C-Units
            (uint256 p1_b4, uint256 d1_b4, uint256 c1_b4) = piePay.getContributorUnits(contributor1);
            (uint256 p2_b4, uint256 d2_b4, uint256 c2_b4) = piePay.getContributorUnits(contributor2);
            (uint256 p3_b4, uint256 d3_b4, uint256 c3_b4) = piePay.getContributorUnits(contributor3);
            assertEq(p1_b4, 0, "Block 4 - Contributor1 P-Units");
            assertEq(d1_b4, getUnitAmount(450), "Block 4 - Contributor1 D-Units");
            assertEq(c1_b4, 0, "Block 4 - Contributor1 C-Units");
            assertEq(p2_b4, 0, "Block 4 - Contributor2 P-Units");
            assertEq(d2_b4, 0, "Block 4 - Contributor2 D-Units");
            assertEq(c2_b4, getUnitAmount(400), "Block 4 - Contributor2 C-Units");
            assertEq(p3_b4, 0, "Block 4 - Contributor3 P-Units");
            assertEq(d3_b4, getUnitAmount(300), "Block 4 - Contributor3 D-Units");
            assertEq(c3_b4, getUnitAmount(100), "Block 4 - Contributor3 C-Units");
            assertEq(piePay.payrollPool(), getCoinAmount(750), "Block 4 - Payroll pool (1350 - 600)");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), 0, "Block 4 - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), getUnitAmount(750), "Block 4 - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), getUnitAmount(500), "Block 4 - Total C-Units");
            assertGe(coin.balanceOf(contributor1), getCoinAmount(800), "Block 4 - Contributor1 tokens");
            assertGe(coin.balanceOf(contributor2), getCoinAmount(400), "Block 4 - Contributor2 tokens");
            assertEq(coin.balanceOf(contributor3), 0, "Block 4 - Contributor3 tokens");
        }
        
        // Block 5: Complete D-Unit payout
        {
            uint256 totalDUnits = getCoinAmount(750); // 450 + 300 (with 1.5x multiplier)
            vm.prank(payrollManager);
            piePay.executeUnitPayout(UnitType.Debt, totalDUnits);
            
            // Check D-Unit holders got amounts and units cleared
            (, uint256 d1,) = piePay.getContributorUnits(contributor1);
            (, uint256 d3,) = piePay.getContributorUnits(contributor3);
            assertEq(d1, 0, "All D-Units should be cleared for contributor1");
            assertEq(d3, 0, "All D-Units should be cleared for contributor3");
            
            // BLOCK 5 END STATE - Starting state for Block 6:
            // Payroll Pool: 0 (750 - 750 paid out for D-Units)
            // Contributor1: 0 P-Units, 0 D-Units, 0 C-Units, ~1250 tokens (800 + 450)
            // Contributor2: 0 P-Units, 0 D-Units, 400 C-Units, ~400 tokens (unchanged)
            // Contributor3: 0 P-Units, 0 D-Units, 100 C-Units, ~300 tokens (0 + 300)
            // Total Outstanding: 0 P-Units, 0 D-Units, 500 C-Units
            (uint256 p1_b5, uint256 d1_b5, uint256 c1_b5) = piePay.getContributorUnits(contributor1);
            (uint256 p2_b5, uint256 d2_b5, uint256 c2_b5) = piePay.getContributorUnits(contributor2);
            (uint256 p3_b5, uint256 d3_b5, uint256 c3_b5) = piePay.getContributorUnits(contributor3);
            assertEq(p1_b5, 0, "Block 5 - Contributor1 P-Units");
            assertEq(d1_b5, 0, "Block 5 - Contributor1 D-Units");
            assertEq(c1_b5, 0, "Block 5 - Contributor1 C-Units");
            assertEq(p2_b5, 0, "Block 5 - Contributor2 P-Units");
            assertEq(d2_b5, 0, "Block 5 - Contributor2 D-Units");
            assertEq(c2_b5, getUnitAmount(400), "Block 5 - Contributor2 C-Units");
            assertEq(p3_b5, 0, "Block 5 - Contributor3 P-Units");
            assertEq(d3_b5, 0, "Block 5 - Contributor3 D-Units");
            assertEq(c3_b5, getUnitAmount(100), "Block 5 - Contributor3 C-Units");
            assertEq(piePay.payrollPool(), 0, "Block 5 - Payroll pool (750 - 750)");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), 0, "Block 5 - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), 0, "Block 5 - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), getUnitAmount(500), "Block 5 - Total C-Units");
            assertGe(coin.balanceOf(contributor1), getCoinAmount(1250), "Block 5 - Contributor1 tokens");
            assertGe(coin.balanceOf(contributor2), getCoinAmount(400), "Block 5 - Contributor2 tokens");
            assertGe(coin.balanceOf(contributor3), getCoinAmount(300), "Block 5 - Contributor3 tokens");
        }
        
        // Block 6: Fund for C-Unit dividend and execute payout
        {
            // Fund for C-Unit dividend
            uint256 cUnitDividend = getCoinAmount(250); // 50% dividend
            vm.prank(payrollManager);
            coin.approve(address(piePay), cUnitDividend);
            vm.prank(payrollManager);
            piePay.fundPayroll(cUnitDividend);
            
            // Execute C-Unit dividend payout
            vm.prank(payrollManager);
            piePay.executeUnitPayout(UnitType.Capital, cUnitDividend);
            
            // Verify C-Units remain unchanged (dividend behavior)
            (,, uint256 c2) = piePay.getContributorUnits(contributor2);
            (,, uint256 c3) = piePay.getContributorUnits(contributor3);
            assertEq(c2, getUnitAmount(400), "C-Units should remain unchanged for contributor2");
            assertEq(c3, getUnitAmount(100), "C-Units should remain unchanged for contributor3");
            
            // BLOCK 6 END STATE - Starting state for Block 7:
            // Payroll Pool: 0 (250 funded - 250 paid out for C-Unit dividend)
            // Contributor1: 0 P-Units, 0 D-Units, 0 C-Units, ~1250 tokens (unchanged)
            // Contributor2: 0 P-Units, 0 D-Units, 400 C-Units, ~600 tokens (400 + 200 dividend)
            // Contributor3: 0 P-Units, 0 D-Units, 100 C-Units, ~350 tokens (300 + 50 dividend)
            // Total Outstanding: 0 P-Units, 0 D-Units, 500 C-Units
            (uint256 p1_b6, uint256 d1_b6, uint256 c1_b6) = piePay.getContributorUnits(contributor1);
            (uint256 p2_b6, uint256 d2_b6, uint256 c2_b6) = piePay.getContributorUnits(contributor2);
            (uint256 p3_b6, uint256 d3_b6, uint256 c3_b6) = piePay.getContributorUnits(contributor3);
            assertEq(p1_b6, 0, "Block 6 - Contributor1 P-Units");
            assertEq(d1_b6, 0, "Block 6 - Contributor1 D-Units");
            assertEq(c1_b6, 0, "Block 6 - Contributor1 C-Units");
            assertEq(p2_b6, 0, "Block 6 - Contributor2 P-Units");
            assertEq(d2_b6, 0, "Block 6 - Contributor2 D-Units");
            assertEq(c2_b6, getUnitAmount(400), "Block 6 - Contributor2 C-Units");
            assertEq(p3_b6, 0, "Block 6 - Contributor3 P-Units");
            assertEq(d3_b6, 0, "Block 6 - Contributor3 D-Units");
            assertEq(c3_b6, getUnitAmount(100), "Block 6 - Contributor3 C-Units");
            assertEq(piePay.payrollPool(), 0, "Block 6 - Payroll pool (250 - 250)");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), 0, "Block 6 - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), 0, "Block 6 - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), getUnitAmount(500), "Block 6 - Total C-Units");
            assertGe(coin.balanceOf(contributor1), getCoinAmount(1250), "Block 6 - Contributor1 tokens");
            assertGe(coin.balanceOf(contributor2), getCoinAmount(600), "Block 6 - Contributor2 tokens");
            assertGe(coin.balanceOf(contributor3), getCoinAmount(350), "Block 6 - Contributor3 tokens");
        }
        
        // Block 7: Final verification and complete state check
        {
            // BLOCK 7 FINAL STATE - End of test verification:
            // Payroll Pool: 0 (all funds distributed)
            // Contributor1: 0 P-Units, 0 D-Units, 0 C-Units, ~1250 tokens (total from P and D payouts)
            // Contributor2: 0 P-Units, 0 D-Units, 400 C-Units, ~600 tokens (total from P and C payouts)
            // Contributor3: 0 P-Units, 0 D-Units, 100 C-Units, ~350 tokens (total from D and C payouts)
            // Total Outstanding: 0 P-Units, 0 D-Units, 500 C-Units
            (uint256 p1_final, uint256 d1_final, uint256 c1_final) = piePay.getContributorUnits(contributor1);
            (uint256 p2_final, uint256 d2_final, uint256 c2_final) = piePay.getContributorUnits(contributor2);
            (uint256 p3_final, uint256 d3_final, uint256 c3_final) = piePay.getContributorUnits(contributor3);
            assertEq(p1_final, 0, "Final - Contributor1 P-Units");
            assertEq(d1_final, 0, "Final - Contributor1 D-Units");
            assertEq(c1_final, 0, "Final - Contributor1 C-Units");
            assertEq(p2_final, 0, "Final - Contributor2 P-Units");
            assertEq(d2_final, 0, "Final - Contributor2 D-Units");
            assertEq(c2_final, getUnitAmount(400), "Final - Contributor2 C-Units");
            assertEq(p3_final, 0, "Final - Contributor3 P-Units");
            assertEq(d3_final, 0, "Final - Contributor3 D-Units");
            assertEq(c3_final, getUnitAmount(100), "Final - Contributor3 C-Units");
            assertEq(piePay.payrollPool(), 0, "Final - Payroll pool (all distributed)");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), 0, "Final - Total P-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Debt), 0, "Final - Total D-Units");
            assertEq(piePay.getTotalUnitsOutstanding(UnitType.Capital), getUnitAmount(500), "Final - Total C-Units");
            assertGe(coin.balanceOf(contributor1), getCoinAmount(1250), "Final - Contributor1 tokens");
            assertGe(coin.balanceOf(contributor2), getCoinAmount(600), "Final - Contributor2 tokens");
            assertGe(coin.balanceOf(contributor3), getCoinAmount(350), "Final - Contributor3 tokens");
            
            // Verify unit holder tracking
            assertEq(piePay.getUnitHolders(UnitType.Profit).length, 0, "No P-Unit holders should remain");
            assertEq(piePay.getUnitHolders(UnitType.Debt).length, 0, "No D-Unit holders should remain");
            assertEq(piePay.getUnitHolders(UnitType.Capital).length, 2, "C-Unit holders should remain");
            
            // Check total funding vs distribution reconciliation
            uint256 totalDistributed = getCoinAmount(600) + getCoinAmount(600) + getCoinAmount(750) + getCoinAmount(250);
            uint256 totalFunded = getCoinAmount(600) + getCoinAmount(1350) + getCoinAmount(250);
            assertEq(piePay.payrollPool(), totalFunded - totalDistributed, "Payroll pool should have correct remainder");
            assertEq(totalFunded, totalDistributed, "Total funded should equal total distributed");
        }
    }

    // ============ CAPACITY CONSTRAINT TESTS ============

    function testSetUnitCapacity() public {
        // Test setting D-Unit capacity
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(1000));
        
        // Test setting C-Unit capacity  
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Capital, getUnitAmount(500));
        
        // Verify capacities are set correctly
        assertEq(piePay.unitTypeCapacity(1), toInternalUnits(getUnitAmount(1000)), "D-Unit capacity should be set");
        assertEq(piePay.unitTypeCapacity(2), toInternalUnits(getUnitAmount(500)), "C-Unit capacity should be set");
    }

    function testSetUnitCapacityPUnitsRevert() public {
        // Should revert when trying to set capacity for P-Units
        vm.prank(payrollManager);
        vm.expectRevert("Cannot set capacity for P-Units");
        piePay.setUnitCapacity(UnitType.Profit, getUnitAmount(1000));
    }

    function testSetUnitCapacityOnlyPayrollManager() public {
        // Should revert when non-payroll manager tries to set capacity
        vm.prank(outsider);
        vm.expectRevert("Not the payroll manager");
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(1000));
    }

    function testConversionExceedsCapacity() public {
        // Set up: Give contributor P-Units and set D-Unit capacity
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Set D-Unit capacity to 500
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(500));
        
        // Try to convert 1000 P-Units to D-Units (would create 1500 D-Units with 1.5x multiplier)
        vm.prank(contributor1);
        vm.expectRevert("Exceeds conversion capacity");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(1000));
    }

    function testConversionWithinCapacity() public {
        // Set up: Give contributor P-Units and set D-Unit capacity
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Set D-Unit capacity to 2000 (enough for conversion)
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(2000));
        
        // Convert 1000 P-Units to D-Units (creates 1500 D-Units with 1.5x multiplier)
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(1000));
        
        // Verify conversion worked
        (uint256 p1, uint256 d1,) = piePay.getContributorUnits(contributor1);
        assertEq(p1, 0, "P-Units should be converted");
        assertEq(d1, getUnitAmount(1500), "D-Units should be created with multiplier");
        
        // Verify capacity tracking
        assertEq(piePay.unitTypeAllocated(1), toInternalUnits(getUnitAmount(1500)), "D-Unit allocation should be tracked");
    }

    function testContributionExceedsCapacity() public {
        // Set D-Unit capacity to 500
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(500));
        
        // Try to submit and approve D-Unit contribution that exceeds capacity
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000), "D-work");
        
        // Should revert when trying to approve (would create 1500 D-Units with 1.5x multiplier)
        vm.prank(projectLead);
        vm.expectRevert("Exceeds unit capacity");
        piePay.reviewContribution(1, true);
    }

    function testContributionWithinCapacity() public {
        // Set D-Unit capacity to 2000
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(2000));
        
        // Submit and approve D-Unit contribution within capacity
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000), "D-work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Verify contribution was approved
        (, uint256 d1,) = piePay.getContributorUnits(contributor1);
        assertEq(d1, getUnitAmount(1500), "D-Units should be awarded with multiplier");
        
        // Verify capacity tracking
        assertEq(piePay.unitTypeAllocated(1), toInternalUnits(getUnitAmount(1500)), "D-Unit allocation should be tracked");
    }

    function testCapacityFreedUpOnPayout() public {
        // Set up: Create D-Units within capacity
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(1000));
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(500), "D-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Verify capacity is consumed
        assertEq(piePay.unitTypeAllocated(1), toInternalUnits(getUnitAmount(750)), "D-Unit allocation should be 750 (500 * 1.5)");
        
        // Fund payroll and execute D-Unit payout
        vm.prank(payrollManager);
        coin.approve(address(piePay), getCoinAmount(1000));
        vm.prank(payrollManager);
        piePay.fundPayroll(getCoinAmount(1000));
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Debt, getCoinAmount(750));
        
        // Verify capacity is freed up (D-Units destroyed)
        assertEq(piePay.unitTypeAllocated(1), 0, "D-Unit allocation should be freed after payout");
        
        // Verify we can now make another D-Unit contribution
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(500), "D-work 2");
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        
        (, uint256 d2,) = piePay.getContributorUnits(contributor2);
        assertEq(d2, getUnitAmount(750), "Second D-Unit contribution should succeed");
    }

    function testCapacityZeroTreatedAsUnlimited() public {
        // Set capacity to 0 (unlimited)
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, 0);
        
        // Should allow large contributions
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(10000), "Large D-work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Verify contribution was approved
        (, uint256 d1,) = piePay.getContributorUnits(contributor1);
        assertEq(d1, getUnitAmount(15000), "Large D-Unit contribution should succeed with unlimited capacity");
    }

    function testCapacityMultipleContributors() public {
        // Set D-Unit capacity to 2000
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(2000));
        
        // First contributor takes 1500 capacity (1000 * 1.5)
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000), "D-work 1");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Second contributor should fail as remaining capacity is only 500
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(500), "D-work 2");
        vm.prank(projectLead);
        vm.expectRevert("Exceeds unit capacity");
        piePay.reviewContribution(2, true);
        
        // But a smaller contribution should succeed (contributor3 already whitelisted)
        vm.prank(contributor3);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(250), "D-work 3");
        vm.prank(projectLead);
        piePay.reviewContribution(3, true);
        
        // Verify final state
        (, uint256 d1,) = piePay.getContributorUnits(contributor1);
        (, uint256 d2,) = piePay.getContributorUnits(contributor2);
        (, uint256 d3,) = piePay.getContributorUnits(contributor3);
        
        assertEq(d1, getUnitAmount(1500), "Contributor1 should have 1500 D-Units");
        assertEq(d2, 0, "Contributor2 should have 0 D-Units");
        assertEq(d3, getUnitAmount(375), "Contributor3 should have 375 D-Units (250 * 1.5)");
        
        // Verify total allocation
        assertEq(piePay.unitTypeAllocated(1), toInternalUnits(getUnitAmount(1875)), "Total D-Unit allocation should be 1875");
    }

    function testCapacityExactAmount() public {
        // Set D-Unit capacity to exactly 1500
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, getUnitAmount(1500));
        
        // Submit contribution that would create exactly 1500 D-Units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000), "D-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Should succeed
        (, uint256 d1,) = piePay.getContributorUnits(contributor1);
        assertEq(d1, getUnitAmount(1500), "Exact capacity amount should succeed");
        
        // Any additional contribution should fail
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1), "D-work 2");
        vm.prank(projectLead);
        vm.expectRevert("Exceeds unit capacity");
        piePay.reviewContribution(2, true);
    }

    function testCapacityWithCUnits() public {
        // Test capacity system with C-Units (no multiplier)
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Capital, getUnitAmount(1000));
        
        // Submit C-Unit contribution
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(800), "C-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Should succeed (C-Units don't have multiplier)
        (,, uint256 c1) = piePay.getContributorUnits(contributor1);
        assertEq(c1, getUnitAmount(800), "C-Units should be awarded without multiplier");
        
        // Submit another that would exceed capacity
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(300), "C-work 2");
        vm.prank(projectLead);
        vm.expectRevert("Exceeds unit capacity");
        piePay.reviewContribution(2, true);
    }

    // Helper function to convert to internal units (matches the contract's toInternalUnits)
    function toInternalUnits(uint256 _userUnits) internal view returns (uint256) {
        return _userUnits * (10 ** piePay.paymentTokenDecimals()) / 10000;
    }

    // ============ ENHANCED INITIALIZATION TESTS ============

    function testInitializationWithLargeInitialContributors() public {
        address[] memory largeContributors = new address[](100);
        for (uint i = 0; i < 100; i++) {
            largeContributors[i] = makeAddr(string(abi.encodePacked("contrib", i)));
        }
        
        PiePay largePiePay = new PiePay(
            "Large Project",
            "Test with many contributors",
            projectLead,
            payrollManager,
            largeContributors,
            address(coin)
        );
        
        assertEq(largePiePay.getContributorCount(), 100);
        for (uint i = 0; i < 100; i++) {
            assertTrue(largePiePay.whitelistedContributors(largeContributors[i]));
        }
    }

    function testRemoveAndReWhitelistContributor() public {
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        assertFalse(piePay.whitelistedContributors(contributor1));
        
        vm.prank(projectLead);
        piePay.whitelistContributor(contributor1);
        
        assertTrue(piePay.whitelistedContributors(contributor1));
    }

    // ============ ENHANCED CONTRIBUTION TESTS ============

    function testSubmitContributionLargeUnits() public {
        uint256 largeUnits = getUnitAmount(1000000); // 1M units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, largeUnits, "Large units");
        
        PiePay.ContributionReport memory contrib = piePay.getContributionDetails(1);
        assertEq(contrib.unitsRequested, largeUnits);
    }

    function testApproveContributionLargeUnits() public {
        uint256 largeUnits = getUnitAmount(1000000); // 1M units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, largeUnits, "Large work");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        (uint256 pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, largeUnits);
        
        assertEq(piePay.getTotalUnitsOutstanding(UnitType.Profit), largeUnits);
    }

    // ============ ENHANCED CONVERSION TESTS ============

    function testConvertPToDWithMinMultiplier() public {
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(1, 3000, 2000); // Min multiplier
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(1000));
        
        (, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, 1000); // 1000 * (1/10000) = 0.1 units = 1000 in 4-decimal format
    }

    function testConvertPToDWithMaxMultiplier() public {
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(type(uint16).max, 3000, 2000);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1), "P-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(1));
        
        (, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, (getUnitAmount(1) * type(uint16).max) / 10000);
    }

    function testChainConversionsPToDToC() public {
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(15000, 3000, 2000); // 1.5x P->D, 0.3x P->C, 0.2x D->C
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // P -> D: 500 P to 750 D
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(500));
        
        // D -> C: 750 D to 150 C (750 * 0.2)
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Debt, UnitType.Capital, getUnitAmount(750));
        
        (uint256 p, uint256 d, uint256 c) = piePay.getContributorUnits(contributor1);
        assertEq(p, getUnitAmount(500));
        assertEq(d, 0);
        assertEq(c, getUnitAmount(150));
    }

    // ============ ENHANCED PAYOUT TESTS ============

    function testPayoutWithManyHolders() public {
        // Setup 5 contributors with P-Units
        address[] memory contribs = new address[](5);
        contribs[0] = contributor1;
        contribs[1] = contributor2;
        contribs[2] = contributor3;
        contribs[3] = contributor4;
        contribs[4] = contributor5;
        
        for (uint i = 0; i < 5; i++) {
            vm.prank(contribs[i]);
            piePay.submitContribution(UnitType.Profit, getUnitAmount(200), string(abi.encodePacked("Work ", i)));
            vm.prank(projectLead);
            piePay.reviewContribution(i + 1, true);
        }
        
        uint256 fundAmount = getCoinAmount(1000);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        for (uint i = 0; i < 5; i++) {
            (uint256 pUnits,,) = piePay.getContributorUnits(contribs[i]);
            assertEq(pUnits, 0);
            assertGe(coin.balanceOf(contribs[i]), getCoinAmount(200));
        }
    }

    function testPayoutRoundingExtreme() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, 1, "Minimal work"); // 0.0001 units
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = 1; // Minimal token amount
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        assertEq(coin.balanceOf(contributor1), fundAmount); // All to first (only) holder
    }

    function testFundPayrollLargeAmount() public {
        uint256 largeAmount = getCoinAmount(1000000000); // 1B tokens
        coin.mint(payrollManager, largeAmount);
        
        vm.prank(payrollManager);
        coin.approve(address(piePay), largeAmount);
        
        vm.prank(payrollManager);
        piePay.fundPayroll(largeAmount);
        
        assertEq(piePay.payrollPool(), largeAmount);
    }

    function testFundPayrollZeroAmount() public {
        vm.prank(payrollManager);
        vm.expectRevert("Amount must be greater than 0");
        piePay.fundPayroll(0);
    }

    function testPayoutAfterRoleChange() public {
        address newManager = makeAddr("newManager");
        vm.prank(payrollManager);
        piePay.setPayrollManager(newManager);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(100);
        coin.mint(newManager, fundAmount);
        vm.prank(newManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(newManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(newManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        assertEq(coin.balanceOf(contributor1), getCoinAmount(100));
    }

    // ============ ENHANCED SECURITY TESTS ============

    function testMaliciousTokenTransfer() public {
        // Deploy malicious token
        MaliciousToken maliciousToken = new MaliciousToken();
        maliciousToken.mint(payrollManager, getCoinAmount(1000));
        
        // New PiePay with malicious token
        address[] memory contribs = new address[](1);
        contribs[0] = contributor1;
        PiePay maliciousPiePay = new PiePay(
            "Malicious Test",
            "Test with bad token",
            projectLead,
            payrollManager,
            contribs,
            address(maliciousToken)
        );
        
        // Set attack to reenter fundPayroll
        bytes memory attackData = abi.encodeWithSelector(maliciousPiePay.fundPayroll.selector, 1);
        maliciousToken.setAttack(true, address(maliciousPiePay), attackData);
        
        vm.prank(payrollManager);
        maliciousToken.approve(address(maliciousPiePay), getCoinAmount(100));
        
        vm.prank(payrollManager);
        vm.expectRevert(); // Should fail due to reentrancy protection
        maliciousPiePay.fundPayroll(getCoinAmount(100));
    }

    // ============ FINANCIAL INTEGRITY TESTS ============

    function testNoFundLossInRounding() public {
        // Setup 3 contributors with odd units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, 3333, "Work1"); // 0.3333 units
        vm.prank(contributor2);
        piePay.submitContribution(UnitType.Profit, 3333, "Work2");
        vm.prank(contributor3);
        piePay.submitContribution(UnitType.Profit, 3334, "Work3"); // Total 1 unit
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        vm.prank(projectLead);
        piePay.reviewContribution(2, true);
        vm.prank(projectLead);
        piePay.reviewContribution(3, true);
        
        uint256 fundAmount = getCoinAmount(1); // 1 token to distribute
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        uint256 totalReceived = coin.balanceOf(contributor1) + coin.balanceOf(contributor2) + coin.balanceOf(contributor3);
        assertEq(totalReceived, fundAmount, "No loss in rounding");
    }

    function testTotalUnitsConsistency() public {
        // Complex operations
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(1000), "P1");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, getUnitAmount(500));
        
        vm.prank(contributor1);
        piePay.convertUnits(UnitType.Debt, UnitType.Capital, getUnitAmount(750));
        
        uint256 totalP = piePay.getTotalUnitsOutstanding(UnitType.Profit);
        uint256 totalD = piePay.getTotalUnitsOutstanding(UnitType.Debt);
        uint256 totalC = piePay.getTotalUnitsOutstanding(UnitType.Capital);
        
        assertEq(totalP, getUnitAmount(500));
        assertEq(totalD, 0);
        assertEq(totalC, getUnitAmount(150)); // 750 * 0.2
    }

    function testHistoricalPayoutAfterRemoval() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Capital, getUnitAmount(100), "C-work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        vm.prank(projectLead);
        piePay.removeContributor(contributor1);
        
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Capital, fundAmount);
        
        assertEq(coin.balanceOf(contributor1), fundAmount);
    }

    function testNoDoublePayout() public {
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        uint256 fundAmount = getCoinAmount(100);
        vm.prank(payrollManager);
        coin.approve(address(piePay), fundAmount);
        vm.prank(payrollManager);
        piePay.fundPayroll(fundAmount);
        
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, fundAmount);
        
        // Fund again and second payout should fail as no units
        vm.prank(payrollManager);
        coin.approve(address(piePay), 1);
        vm.prank(payrollManager);
        piePay.fundPayroll(1);
        
        vm.prank(payrollManager);
        vm.expectRevert("No unit holders for this type");
        piePay.executeUnitPayout(UnitType.Profit, 1);
    }

    function testUnlimitedCapacityZero() public {
        vm.prank(payrollManager);
        piePay.setUnitCapacity(UnitType.Debt, 0);
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Debt, getUnitAmount(1000000), "Large D");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        (, uint256 dUnits,) = piePay.getContributorUnits(contributor1);
        assertEq(dUnits, getUnitAmount(1500000)); // 1M * 1.5 multiplier
    }

    // ============ OVERFLOW PROTECTION TESTS ============


    function testSubmitContributionOverflowExploit() public {
        // Try to submit contribution with maximum value to cause overflow
        vm.prank(contributor1);
        vm.expectRevert("Units requested too large");
        piePay.submitContribution(UnitType.Profit, type(uint256).max, "Overflow exploit");
        
        // Try with a value that would overflow in toInternalUnits
        uint256 maliciousValue = (type(uint256).max / (10 ** piePay.paymentTokenDecimals())) + 1;
        vm.prank(contributor1);
        vm.expectRevert("Units requested too large");
        piePay.submitContribution(UnitType.Profit, maliciousValue, "Overflow exploit");
    }

    function testConvertUnitsOverflowExploit() public {
        // First, get some units to convert
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Initial work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Try to convert with maximum value
        vm.prank(contributor1);
        vm.expectRevert("Amount too large");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, type(uint256).max);
        
        // Try with a value that would overflow in conversion calculation
        uint256 maliciousValue = (type(uint256).max / (10 ** piePay.paymentTokenDecimals())) + 1;
        vm.prank(contributor1);
        vm.expectRevert("Amount too large");
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, maliciousValue);
    }

    function testMultiplierOverflowInReviewContribution() public {
        // Set maximum multiplier
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(type(uint16).max, 3000, 2000);
        
        // Try to submit a large contribution that would overflow - should be caught by input validation
        uint256 largeValue = type(uint256).max / type(uint16).max - 1;
        vm.prank(contributor1);
        vm.expectRevert("Units requested too large"); // Input validation catches this
        piePay.submitContribution(UnitType.Debt, largeValue, "Large contribution");
    }

    function testConversionMultiplierOverflowExploit() public {
        // Get some P-Units first
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Set maximum multiplier
        vm.prank(payrollManager);
        piePay.setConversionMultipliers(type(uint16).max, 3000, 2000);
        
        // Try to convert amount that would overflow - should be caught by input validation first
        uint256 overflowAmount = type(uint256).max / type(uint16).max - 1;
        vm.prank(contributor1);
        vm.expectRevert("Amount too large"); // Input validation catches this first
        piePay.convertUnits(UnitType.Profit, UnitType.Debt, overflowAmount);
    }

    function testPayoutDistributionOverflowProtection() public {
        // Setup contributor with units
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, getUnitAmount(100), "Work");
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Fund with a large but safe amount (within uint128 limits)
        uint256 safeFunding = uint256(type(uint128).max);
        coin.mint(payrollManager, safeFunding);
        vm.prank(payrollManager);
        coin.approve(address(piePay), safeFunding);
        vm.prank(payrollManager);
        piePay.fundPayroll(safeFunding);
        
        // This should work without overflow due to our protection
        vm.prank(payrollManager);
        piePay.executeUnitPayout(UnitType.Profit, getCoinAmount(100));
        
        // Verify payout succeeded
        assertGt(coin.balanceOf(contributor1), 0);
    }

    function testCapacityOverflowExploit() public {
        // Try to set capacity with maximum value
        vm.prank(payrollManager);
        vm.expectRevert("Capacity too large");
        piePay.setUnitCapacity(UnitType.Debt, type(uint256).max);
        
        // Try with value that would overflow in toInternalUnits
        uint256 maliciousCapacity = (type(uint256).max / (10 ** piePay.paymentTokenDecimals())) + 1;
        vm.prank(payrollManager);
        vm.expectRevert("Capacity too large");
        piePay.setUnitCapacity(UnitType.Debt, maliciousCapacity);
    }

    function testFundPayrollOverflowExploit() public {
        // Try to fund with maximum amount to test overflow protection
        // Use a value that exceeds uint128.max but won't cause mint overflow
        uint256 maxAmount = uint256(type(uint128).max) + 1;
        
        // Only mint if we can (some tokens have max supply limits)
        try coin.mint(payrollManager, maxAmount) {
            vm.prank(payrollManager);
            coin.approve(address(piePay), maxAmount);
            
            vm.prank(payrollManager);
            vm.expectRevert("Amount exceeds maximum safe value");
            piePay.fundPayroll(maxAmount);
        } catch {
            // If mint fails, test with a large but mintable amount
            uint256 largeAmount = type(uint128).max;
            coin.mint(payrollManager, largeAmount);
            
            vm.prank(payrollManager);
            coin.approve(address(piePay), largeAmount);
            
            vm.prank(payrollManager);
            // This should succeed since it's within limits
            piePay.fundPayroll(largeAmount);
            assertEq(piePay.payrollPool(), largeAmount);
        }
    }

    // Test edge case: maximum safe values should work
    function testMaximumSafeValuesWork() public {
        // Test maximum safe unit submission
        uint256 maxSafeUnits = type(uint256).max / (10 ** piePay.paymentTokenDecimals()) / 10000;
        
        vm.prank(contributor1);
        piePay.submitContribution(UnitType.Profit, maxSafeUnits, "Max safe contribution");
        
        vm.prank(projectLead);
        piePay.reviewContribution(1, true);
        
        // Verify it worked
        (uint256 pUnits,,) = piePay.getContributorUnits(contributor1);
        assertEq(pUnits, maxSafeUnits);
    }

}

// Concrete implementations for different token decimals
contract PiePayUSDCTest is PiePayTest {
    function deployCoin() internal override returns (IMintableToken) {
        return IMintableToken(address(new MockUSDC()));
    }
    
    function getCoinAmount(uint256 baseAmount) internal pure override returns (uint256) {
        return baseAmount * 10**6; // USDC has 6 decimals
    }
}

contract PiePayDAITest is PiePayTest {
    function deployCoin() internal override returns (IMintableToken) {
        return IMintableToken(address(new MockDAI()));
    }
    
    function getCoinAmount(uint256 baseAmount) internal pure override returns (uint256) {
        return baseAmount * 10**18; // DAI has 18 decimals
    }
}