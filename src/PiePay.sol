// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/console.sol";

/**
 * @title PiePay
 * @dev Manages team contributions with minute tracking and internal unit-based compensation
 * Based on the Gardens/PiePay proposal for fair team payouts
 * Uses internal integer accounting instead of transferable tokens
 */
contract PiePay is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable paymentUnit; // e.g. USDC contract

    //ISplitMain public immutable splitMain;
    // Enums
    enum ContributionStatus {
        None,    // Default state
        Pending,  // Submitted and awaiting review
        Approved, // Approved by project lead
        Rejected  // Rejected by project lead
    }
    
    // Structs
    struct ContributionReport {
        uint256 minutesWorked;
        uint8 valuationFactor; // 1-5 scale
        string description;
        ContributionStatus status;
        uint256 timestamp;
        address contributor;
        string leadComment; // Comment from project lead on approval/rejection
        uint256 pUnitsEarned; // P-Units earned from this contribution
    }
    
    struct ValuationRubric {
        uint256 factor1Rate; // Minute rate for valuation factor 1
        uint256 factor2Rate; // Minute rate for valuation factor 2
        uint256 factor3Rate; // Minute rate for valuation factor 3
        uint256 factor4Rate; // Minute rate for valuation factor 4
        uint256 factor5Rate; // Minute rate for valuation factor 5
    }
    
    // State Variables
    string public projectName;
    string public projectDescription;
    
    // Role addresses
    address public projectLead;
    address public payrollManager;
    
    // Contributor whitelist
    mapping(address => bool) public whitelistedContributors;
    address[] public contributorList;
    
    // Internal unit balances (stored as integers, not transferable)
    mapping(address => uint256) public pUnits; // Profit Units
    mapping(address => uint256) public dUnits; // Debt Units
    mapping(address => uint256) public cUnits; // Capital Units (future feature)
    
    // Contribution tracking
    mapping(uint256 => ContributionReport) public contributions;
    uint256 public contributionCounter;
    
    // Distribution tracking
    uint256 public distributionCounter;
    mapping(uint256 => uint256) public distributionTimestamps;
    
    // Project configuration
    ValuationRubric public valuationRubric;
    uint256 public payrollPool; // Internal accounting for available funds
    
    // Constants (simple dollar values)
    uint256 public constant P_TOKEN_VALUE = 1; // $1 per P-Unit
    uint256 public constant D_TOKEN_VALUE = 1; // $1 per D-Unit
    uint256 public constant C_TOKEN_VALUE = 5; // $5 per C-Unit
    
    // Whitelisting
    event ProjectInitialized(string name, string description);
    event ContributorWhitelisted(address indexed contributor);
    event ContributorRemoved(address indexed contributor);

    // Contribution Reports
    event ContributionSubmitted(uint256 indexed contributionId, address indexed contributor, uint256 minutesWorked, uint8 factor);
    event ContributionReviewed(uint256 indexed contributionId, address approver, bool approved, string comment);

    // Payroll Management
    event PayrollFunded(uint256 amount);

    event PUnitsIssued(address indexed contributor, uint256 amount, uint256 contributionId);
    event DistributionExecuted(uint256 indexed distributionId, uint256 pUnitsPurchased, uint256 dUnitsIssued);
    event PaymentProcessed(address indexed contributor, uint256 pUnits, uint256 dUnits, uint256 amount);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    
    // Modifiers
    modifier onlyProjectLead() {
        require(msg.sender == projectLead, "Not the project lead");
        _;
    }
    
    modifier onlyPayrollManager() {
        require(msg.sender == payrollManager, "Not the payroll manager");
        _;
    }
    
    modifier onlyWhitelistedContributor() {
        require(whitelistedContributors[msg.sender], "Not a whitelisted contributor");
        _;
    }
    
    constructor(
        string memory _projectName,
        string memory _projectDescription,
        address _projectLead,
        address _payrollManager,
        address[] memory _initialContributors,
        ValuationRubric memory _valuationRubric,
        address _paymentUnit
        //address _splitMainAddress
    ) {
        projectName = _projectName;
        projectDescription = _projectDescription;
        projectLead = _projectLead;
        payrollManager = _payrollManager;
        valuationRubric = _valuationRubric;
        
        paymentUnit = IERC20(_paymentUnit);
        //splitMain = ISplitMain(_splitMainAddress); 

        // Whitelist initial contributors
        for (uint i = 0; i < _initialContributors.length; i++) {
            _whitelistContributor(_initialContributors[i]);
        }
        
        emit ProjectInitialized(_projectName, _projectDescription);
    }
    
    // Contributor Management
    function whitelistContributor(address _contributor) external onlyProjectLead {
        _whitelistContributor(_contributor);
    }
    
    function _whitelistContributor(address _contributor) private {
        require(!whitelistedContributors[_contributor], "Already whitelisted");
        whitelistedContributors[_contributor] = true;
        contributorList.push(_contributor);
        emit ContributorWhitelisted(_contributor);
    }
    
    function removeContributor(address _contributor) external onlyProjectLead {
        require(whitelistedContributors[_contributor], "Not whitelisted");
        whitelistedContributors[_contributor] = false;
        
        // Remove from contributor list
        for (uint i = 0; i < contributorList.length; i++) {
            if (contributorList[i] == _contributor) {
                contributorList[i] = contributorList[contributorList.length - 1];
                contributorList.pop();
                break;
            }
        }
        
        emit ContributorRemoved(_contributor);
    }
    
    // Contribution Reporting
    function submitContribution(
        uint256 _minutesWorked,
        uint8 _valuationFactor,
        string calldata _description
    ) external onlyWhitelistedContributor {
        require(_minutesWorked > 0, "Minutes must be greater than 0");
        require(_valuationFactor >= 1 && _valuationFactor <= 5, "Valuation factor must be 1-5");
        
        contributionCounter++;
        
        contributions[contributionCounter] = ContributionReport({
            minutesWorked: _minutesWorked,
            valuationFactor: _valuationFactor,
            description: _description,
            status: ContributionStatus.Pending,
            timestamp: block.timestamp,
            contributor: msg.sender,
            leadComment: "",
            pUnitsEarned: 0
        });
        
        emit ContributionSubmitted(contributionCounter, msg.sender, _minutesWorked, _valuationFactor);
    }
    
    function reviewContribution(
        uint256 _contributionId,
        bool _approved,
        string calldata _comment
    ) external onlyProjectLead {
        require(_contributionId > 0 && _contributionId <= contributionCounter, "Invalid contribution ID");
        
        ContributionReport storage contribution = contributions[_contributionId];
        require(!(contribution.status == ContributionStatus.Approved), "Contribution already approved");
        
        contribution.leadComment = _comment;
        
        if (_approved) {
            contribution.status = ContributionStatus.Approved;
            
            // Calculate P-Units based on hours and valuation factor
            uint256 minuteRate = _getMinuteRate(contribution.valuationFactor);
            uint256 pUnitsToIssue = (contribution.minutesWorked * minuteRate) ;
            
            contribution.pUnitsEarned = pUnitsToIssue;
            pUnits[contribution.contributor] += pUnitsToIssue;
            
            emit PUnitsIssued(contribution.contributor, pUnitsToIssue, _contributionId);
        } else {
            contribution.status = ContributionStatus.Rejected;
        }
        
        emit ContributionReviewed(_contributionId, msg.sender, _approved, _comment);
    }
    
    function _getMinuteRate(uint8 _factor) private view returns (uint256) {
        if (_factor == 1) return valuationRubric.factor1Rate;
        if (_factor == 2) return valuationRubric.factor2Rate;
        if (_factor == 3) return valuationRubric.factor3Rate;
        if (_factor == 4) return valuationRubric.factor4Rate;
        if (_factor == 5) return valuationRubric.factor5Rate;
        revert("Invalid valuation factor");
    }
    
    // Payroll Management
    function fundPayroll(uint256 _amount) external onlyPayrollManager {
        require(_amount > 0, "Amount must be greater than 0");
        // Transfer USDC from payroll manager to this contract
        paymentUnit.safeTransferFrom(msg.sender, address(this), _amount);

        // Get token decimals and convert to internal 18-decimal accounting
        // uint8 tokenDecimals = IERC20Metadata(address(paymentUnit)).decimals();
        // uint256 normalizedAmount = _normalizeToInternal(_amount, tokenDecimals);

        payrollPool += _amount;

        emit PayrollFunded(_amount);
    }
    
    function executePUnitPayout() external onlyPayrollManager nonReentrant
    {

        // sum PUnits across all contributors
        require(contributorList.length > 0, "No contributors to distribute to");
        uint256 totalPUnits = 0;
        uint256 activeContributors = 0;

        for (uint i = 0; i < contributorList.length; i++) {
            uint256 curPUnits = pUnits[contributorList[i]];
            totalPUnits += curPUnits;
            if (curPUnits > 0){
                activeContributors++; // Count active contributors
            }
        }

        require(activeContributors > 0, "No active contributors");
        require(totalPUnits > 0, "No P-Units to distribute");
        require(payrollPool > 0, "No funds available");

        uint8 tokenDecimals = IERC20Metadata(address(paymentUnit)).decimals();
        uint256 decimalMultiplier = 10 ** (18 - tokenDecimals); // e.g. for USDC's 6 decimals, divide by 10^12 to convert to 18 decimals

        // Calculate how much can be paid 
        uint256 maxPUnitsPurchasable = payrollPool * decimalMultiplier; 
        uint256 pUnitsToPurchase = totalPUnits <= maxPUnitsPurchasable ? totalPUnits : maxPUnitsPurchasable;
        uint256 totalTokenAmount = pUnitsToPurchase / decimalMultiplier; // Convert to token amount 

        console.log("token balance", paymentUnit.balanceOf(address(this)));
        console.log("totalTokenAmount", totalTokenAmount);

        // Verify contract has sufficient token balance
        require(paymentUnit.balanceOf(address(this)) >= totalTokenAmount, "Insufficient token balance");

        // Track total distributed for rounding adjustment
        uint256 totalDistributed = 0;
        address firstActiveContributor = address(0);

        console.log("maxPUnitsPurchasable:", maxPUnitsPurchasable);
        console.log("totalPUnits:", totalPUnits);
        console.log("Active Contributors:", activeContributors);
        console.log("contributorList.length:", contributorList.length);
        console.log("Payroll Pool:", payrollPool);
        console.log("decimalMultiplier", decimalMultiplier);
        console.log("P-Units to Purchase:", pUnitsToPurchase);

        // Calculate allocations and update balances
        // Process all contributors except the first active one
        for (uint i = 0; i < contributorList.length; i++) {
            address contributor = contributorList[i];
            uint256 contributorPUnits = pUnits[contributor];
            
            if (contributorPUnits > 0) {
                // Calculate proportional share in internal decimals
                uint256 contributorShareInternal = (contributorPUnits * pUnitsToPurchase) / totalPUnits;
                
                // Convert to token decimals
                uint256 contributorTokenAmount = contributorShareInternal / decimalMultiplier;
                
                if (firstActiveContributor == address(0)) {
                    // This is the first active contributor - save for last
                    firstActiveContributor = contributor;
                } else {
                    // Distribute to all other contributors
                    if (contributorTokenAmount > 0) {
                        paymentUnit.safeTransfer(contributor, contributorTokenAmount);
                        totalDistributed += contributorTokenAmount;
                    }
                }
                
                pUnits[contributor] -= contributorShareInternal;
                
                emit PaymentProcessed(contributor, contributorShareInternal, 0, contributorShareInternal);
            }
        }

        // Send remaining balance to first active contributor (includes any rounding dust)
        if (firstActiveContributor != address(0)) {
            uint256 remainingAmount = totalTokenAmount - totalDistributed;
            if (remainingAmount > 0) {
                paymentUnit.safeTransfer(firstActiveContributor, remainingAmount);
            }
        }

        // Update internal accounting
        payrollPool -= (pUnitsToPurchase / decimalMultiplier);
        
        // Increment distribution counter and record timestamp
        distributionCounter++;
        distributionTimestamps[distributionCounter] = block.timestamp;
        
        emit DistributionExecuted(distributionCounter, pUnitsToPurchase, 0);
    }

    // Add this mapping to store split addresses
    mapping(uint256 => address) public distributionSplits;

    // Add this event
    event SplitCreated(uint256 indexed distributionId, address indexed split, uint256 usdcAmount);
    
    // Administrative Functions
    function withdrawFunds(address _recipient, uint256 _amount) external onlyPayrollManager {
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount <= payrollPool, "Insufficient funds");
        require(_recipient != address(0), "Invalid recipient");
        
        payrollPool -= _amount;
        emit FundsWithdrawn(_recipient, _amount);
        
        // In a real implementation, this would transfer actual funds to the recipient
        // For now, we just emit the event to track the withdrawal
    }
    
    // Configuration Functions
    function updateValuationRubric(ValuationRubric calldata _newRubric) external onlyProjectLead {
        valuationRubric = _newRubric;
    }
    
    function setProjectLead(address _newLead) external onlyProjectLead {
        require(_newLead != address(0), "Invalid address");
        projectLead = _newLead;
    }
    
    function setPayrollManager(address _newManager) external onlyPayrollManager {
        require(_newManager != address(0), "Invalid address");
        payrollManager = _newManager;
    }
    
    // View Functions
    function getPendingContributions() external view returns (uint256[] memory) {
        uint256 pendingCount = 0;
        
        // Count pending contributions
        for (uint i = 1; i <= contributionCounter; i++) {
            if (contributions[i].status == ContributionStatus.Pending) {
                pendingCount++;
            }
        }
        
        // Collect pending contribution IDs
        uint256[] memory pendingIds = new uint256[](pendingCount);
        uint256 index = 0;
        
        for (uint i = 1; i <= contributionCounter; i++) {
            if (contributions[i].status == ContributionStatus.Pending) {
                pendingIds[index] = i;
                index++;
            }
        }
        
        return pendingIds;
    }
    
    function getContributorUnits(address _contributor) external view returns (
        uint256 profitUnits,
        uint256 debtUnits,
        uint256 capitalUnits
    ) {
        return (pUnits[_contributor], dUnits[_contributor], cUnits[_contributor]);
    }
    
    function getCurrentDistributionInfo() external view returns (
        uint256 totalPUnits,
        uint256 totalDUnits,
        uint256 availableFunds,
        uint256 lastDistributionTime
    ) {
        // Calculate total P-Units across all contributors
        for (uint i = 0; i < contributorList.length; i++) {
            address contributor = contributorList[i];
            totalPUnits += pUnits[contributor];
            totalDUnits += dUnits[contributor];
        }
        
        return (
            totalPUnits,
            totalDUnits,
            payrollPool,
            distributionCounter > 0 ? distributionTimestamps[distributionCounter] : 0
        );
    }
    
    function getTotalUnitDistribution() external view returns (
        uint256 totalPUnits,
        uint256 totalDUnits,
        uint256 totalCUnits
    ) {
        for (uint i = 0; i < contributorList.length; i++) {
            address contributor = contributorList[i];
            totalPUnits += pUnits[contributor];
            totalDUnits += dUnits[contributor];
            totalCUnits += cUnits[contributor];
        }
    }
    
    function getContributorCount() external view returns (uint256) {
        return contributorList.length;
    }

    // Helper function to convert token amounts to internal 18-decimal representation
    function _normalizeToInternal(uint256 _tokenAmount, uint8 _tokenDecimals) private pure returns (uint256) {
        if (_tokenDecimals <= 18) {
            return _tokenAmount * (10 ** (18 - _tokenDecimals));
        } else {
            return _tokenAmount / (10 ** (_tokenDecimals - 18));
        }
    }

    // Helper function to convert internal amounts back to token decimals
    function _normalizeToToken(uint256 _internalAmount, uint8 _tokenDecimals) private pure returns (uint256) {
        if (_tokenDecimals <= 18) {
            return _internalAmount / (10 ** (18 - _tokenDecimals));
        } else {
            return _internalAmount * (10 ** (_tokenDecimals - 18));
        }
    }
}