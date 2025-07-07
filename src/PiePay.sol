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
 * @dev Manages team contributions with internal unit-based compensation
 * Uses internal integer accounting instead of transferable tokens
 */
contract PiePay is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable paymentUnit; // e.g. USDC contract
    uint8 paymentUnitDecimals;

    // Enums
    enum ContributionStatus {
        None,    // Default state
        Pending,  // Submitted and awaiting review
        Approved, // Approved by project lead
        Rejected  // Rejected by project lead
    }
    
    // Structs
    struct ContributionReport {
        address contributor;
        uint256 pUnitsClaimed; // P-Units claimed by contributor
        ContributionStatus status;
        string description;
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
    event ContributionSubmitted(uint256 indexed contributionId, address indexed contributor, string description, uint256 pUnitsClaimed);
    event ContributionReviewed(uint256 indexed contributionId, address approver, bool approved);

    // Payroll Management
    event PayrollFunded(uint256 amount);

    event PUnitsIssued(address indexed contributor, uint256 amount, uint256 contributionId);
    event DistributionExecuted(uint256 indexed distributionId, uint256 pUnitsPurchased, uint256 dUnitsIssued);
    event PaymentProcessed(address indexed contributor, uint256 pUnits, uint256 dUnits, uint256 amount);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    
    event DUnitsGranted( address indexed contributor,  uint256 amount, string reason, uint256 timestamp);
    event DUnitsPurchased(address indexed contributor, uint256 paymentAmount, uint256 dUnitsReceived, uint256 multiplier, uint256 timestamp);
    event DUnitsPaidOut(address indexed contributor, uint256 dUnitsRedeemed, uint256 tokenAmount, uint256 timestamp);
    event PUnitsConvertedToDebt(address indexed contributor, uint256 pUnitsConverted, uint256 dUnitsGranted, uint256 multiplier, uint256 timestamp);
    event DUnitDistributionExecuted(uint256 indexed distributionId, uint256 totalDUnitsRedeemed, uint256 totalTokensDistributed, uint256 timestamp);

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
        address _paymentUnit
        //address _splitMainAddress
    ) {
        projectName = _projectName;
        projectDescription = _projectDescription;
        projectLead = _projectLead;
        payrollManager = _payrollManager;
        
        paymentUnit = IERC20(_paymentUnit);
        paymentUnitDecimals = IERC20Metadata(address(paymentUnit)).decimals();
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
        uint256 _pUnitsClaimed,
        string calldata _description
    ) external onlyWhitelistedContributor {
        contributionCounter++;
        
        contributions[contributionCounter] = ContributionReport({
            contributor: msg.sender,
            pUnitsClaimed: _pUnitsClaimed,
            status: ContributionStatus.Pending,
            description: _description
        });
        
        emit ContributionSubmitted(contributionCounter, msg.sender, _description, _pUnitsClaimed);
    }
    
    function reviewContribution(
        uint256 _contributionId,
        bool _approved
    ) external onlyProjectLead {
        require(_contributionId > 0 && _contributionId <= contributionCounter, "Invalid contribution ID");
        
        ContributionReport storage contribution = contributions[_contributionId];
        require(!(contribution.status == ContributionStatus.Approved), "Contribution already approved");
        
        if (_approved) {
            contribution.status = ContributionStatus.Approved;
            pUnits[contribution.contributor] += contribution.pUnitsClaimed;
            
            emit PUnitsIssued(contribution.contributor, contribution.pUnitsClaimed, _contributionId);
        } else {
            contribution.status = ContributionStatus.Rejected;
        }
        
        emit ContributionReviewed(_contributionId, msg.sender, _approved);
    }

    /**
    * @dev Grant D units to a contributor for unpaid work
    * @param contributor Address of the contributor
    * @param amount Amount of D units to grant (in 18 decimals)
    * @param reason Description of why D units are being granted
    */
    function grantDUnits(
        address contributor, 
        uint256 amount, 
        string calldata reason
    ) external onlyPayrollManager() {
        require(whitelistedContributors[contributor], "Not a whitelisted contributor");
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(reason).length > 0, "Reason cannot be empty");
        
        // Grant D units to the contributor
        dUnits[contributor] += amount;
        
        // Emit event for tracking
        emit DUnitsGranted(
            contributor,
            amount,
            reason,
            block.timestamp
        );
    }

    /**
     * @dev Purchase D units by paying into the contract
     * @param paymentAmount Amount of tokens to pay (in token decimals)
     * @param multiplier Bonus multiplier for D units received (scaled by 1000, e.g., 1500 = 1.5x)
     */
    function purchaseDUnits(
        uint256 paymentAmount, 
        uint256 multiplier
    ) external onlyWhitelistedContributor {
        require(paymentAmount > 0, "Payment amount must be greater than 0");
        require(multiplier > 0, "Multiplier must be greater than 0");
        
        // Transfer payment tokens from user to contract
        paymentUnit.safeTransferFrom(msg.sender, address(this), paymentAmount);
        
        // Convert payment amount to internal 18-decimal representation
        uint256 normalizedPayment = _normalizeToInternal(paymentAmount, paymentUnitDecimals);
        
        // Apply multiplier (scaled by 1000, so 1500 = 1.5x bonus)
        uint256 dUnitsReceived = (normalizedPayment * multiplier);
        
        // Update user's D unit balance
        dUnits[msg.sender] += dUnitsReceived;
        
        // Add funds to payroll pool for tracking
        payrollPool += paymentAmount;
        
        // Emit purchase event
        emit DUnitsPurchased(
            msg.sender,
            paymentAmount,
            dUnitsReceived,
            multiplier,
            block.timestamp
        );
    }

    /**
    * @dev Execute payout to D unit holders (proportional buyback) - all funds
    */
    function executeDUnitPayout() external onlyPayrollManager nonReentrant {
        _executeDUnitPayoutInternal(type(uint256).max);
    }

    /**
    * @dev Execute payout to D unit holders (proportional buyback) - specific amount
    * @param distributionAmount Amount to distribute (use type(uint256).max for all funds)
    */
    function executeDUnitPayoutAmount(uint256 distributionAmount) external onlyPayrollManager nonReentrant {
        _executeDUnitPayoutInternal(distributionAmount);
    }

    /**
    * @dev Internal function to execute D unit payout with amount parameter
    * @param distributionAmount Amount to distribute (type(uint256).max for all funds)
    */
    function _executeDUnitPayoutInternal(uint256 distributionAmount) internal {
        require(payrollPool > 0, "No funds available");
        require(contributorList.length > 0, "No contributors to distribute to");
        
        // Calculate total D-Units from active contributors
        (uint256 totalActiveDUnits, uint256 activeContributorCount) = _calculateTotalActiveDUnits();
        
        require(activeContributorCount > 0, "No active D-Unit holders");
        require(totalActiveDUnits > 0, "No D-Units to distribute");
        
        // Determine distribution amount - use all funds if amount is maxed out
        uint256 targetDistributionAmount = distributionAmount == type(uint256).max 
            ? payrollPool 
            : distributionAmount;
        
        require(targetDistributionAmount > 0, "Distribution amount must be greater than 0");
        require(targetDistributionAmount <= payrollPool, "Distribution amount exceeds available funds");
        
        // Determine how much we can actually pay out
        uint256 maxAffordableDUnits = _normalizeToInternal(targetDistributionAmount, paymentUnitDecimals);
        uint256 dUnitsToDistribute = totalActiveDUnits <= maxAffordableDUnits 
            ? totalActiveDUnits 
            : maxAffordableDUnits;
        uint256 totalTokensToDistribute = _normalizeToToken(dUnitsToDistribute, paymentUnitDecimals);
        
        // Verify sufficient balance
        require(paymentUnit.balanceOf(address(this)) >= totalTokensToDistribute, "Insufficient token balance");
        
        _logDUnitDistributionDetails(maxAffordableDUnits, totalActiveDUnits, activeContributorCount, dUnitsToDistribute, totalTokensToDistribute);
        
        // Execute the distribution
        uint256 totalTokensDistributed = _distributeToDUnitHolders(dUnitsToDistribute, totalActiveDUnits, totalTokensToDistribute);
        
        // Update contract state
        _updateContractStateForDUnits(totalTokensToDistribute);
        
        emit DUnitDistributionExecuted(distributionCounter, dUnitsToDistribute, totalTokensDistributed, block.timestamp);
    }

    function _calculateTotalActiveDUnits() private view returns (uint256 totalDUnits, uint256 activeCount) {
        for (uint i = 0; i < contributorList.length; i++) {
            uint256 contributorDUnits = dUnits[contributorList[i]];
            if (contributorDUnits > 0) {
                totalDUnits += contributorDUnits;
                activeCount++;
            }
        }
    }

    function _distributeToDUnitHolders(
        uint256 dUnitsToDistribute, 
        uint256 totalActiveDUnits, 
        uint256 totalTokensToDistribute
    ) private returns (uint256 totalTokensDistributed) {
        address firstActiveContributor = address(0);
        uint8 tokenDecimals = paymentUnitDecimals; 
        
        // Process all contributors except the first active one
        for (uint i = 0; i < contributorList.length; i++) {
            address contributor = contributorList[i];
            uint256 contributorDUnits = dUnits[contributor];
            
            if (contributorDUnits > 0) {
                // Calculate this contributor's share in internal decimals
                uint256 dUnitShareToDeduct = (contributorDUnits * dUnitsToDistribute) / totalActiveDUnits;
                uint256 tokenAmountToTransfer = _normalizeToToken(dUnitShareToDeduct, tokenDecimals);
                
                if (firstActiveContributor == address(0)) {
                    // Save first active contributor for rounding adjustment
                    firstActiveContributor = contributor;
                    console.log("First active D-Unit holder:", firstActiveContributor);
                } else {
                    // Distribute to all other contributors
                    if (tokenAmountToTransfer > 0) {
                        console.log("Distributing to D-Unit holder:", contributor, "Amount:", tokenAmountToTransfer);
                        paymentUnit.safeTransfer(contributor, tokenAmountToTransfer);
                        totalTokensDistributed += tokenAmountToTransfer;
                        
                        console.log("Reducing D Unit balance:", dUnits[contributor], "by", dUnitShareToDeduct);
                        dUnits[contributor] -= dUnitShareToDeduct;
                        console.log("New D Unit balance:", dUnits[contributor]);
                    }
                }
                
                emit DUnitsPaidOut(contributor, dUnitShareToDeduct, tokenAmountToTransfer, block.timestamp);
            }
        }
        
        // Handle first active contributor with remaining amount (includes rounding dust)
        if (firstActiveContributor != address(0)) {
            uint256 remainingTokenAmount = totalTokensToDistribute - totalTokensDistributed;
            if (remainingTokenAmount > 0) {
                console.log("Distributing remaining to D-Unit holder:", firstActiveContributor, "Amount:", remainingTokenAmount);
                paymentUnit.safeTransfer(firstActiveContributor, remainingTokenAmount);
                
                // Convert remaining token amount back to internal decimals before deducting
                uint256 remainingDUnitsToDeduct = _normalizeToInternal(remainingTokenAmount, tokenDecimals);
                console.log("Reducing D Unit balance:", dUnits[firstActiveContributor], "by", remainingDUnitsToDeduct);
                dUnits[firstActiveContributor] -= remainingDUnitsToDeduct;
                console.log("New D Unit balance:", dUnits[firstActiveContributor]);
            }
        }
        
        return totalTokensDistributed;
    }

    function _updateContractStateForDUnits(uint256 totalTokensDistributed) private {
        payrollPool -= totalTokensDistributed;
        distributionCounter++;
        distributionTimestamps[distributionCounter] = block.timestamp;
    }

    function _logDUnitDistributionDetails(
        uint256 maxAffordableDUnits, 
        uint256 totalActiveDUnits, 
        uint256 activeContributorCount, 
        uint256 dUnitsToDistribute,
        uint256 totalTokensToDistribute
    ) private view {
        uint8 tokenDecimals = paymentUnitDecimals; 
        console.log("=== D-Unit Distribution Details ===");
        console.log("token balance", paymentUnit.balanceOf(address(this)));
        console.log("maxAffordableDUnits", maxAffordableDUnits);
        console.log("dUnitsToDistribute", dUnitsToDistribute);
        console.log("totalTokensToDistribute", totalTokensToDistribute);
        console.log("totalTokenAmount", _normalizeToToken(dUnitsToDistribute, tokenDecimals));
        console.log("totalActiveDUnits:", totalActiveDUnits);
        console.log("Active D-Unit Contributors:", activeContributorCount);
        console.log("contributorList.length:", contributorList.length);
        console.log("Payroll Pool:", payrollPool);
        console.log("Token Decimals:", tokenDecimals);
    }

    /**
    * @dev Convert specific amounts of P units to D units for contributors
    * @param contributors Array of contributor addresses
    * @param pUnitsToConvert Amount of P units to convert (same for all contributors)
    * @param multiplier Conversion multiplier (P units * multiplier = D units)
    */
    function convertPUnitsToDebt(
        address[] calldata contributors,
        uint256 pUnitsToConvert, 
        uint256 multiplier
    ) external onlyPayrollManager {
        require(contributors.length > 0, "No contributors specified");
        require(pUnitsToConvert > 0, "Amount must be greater than 0");
        require(multiplier > 0, "Multiplier must be greater than 0");
        
        uint256 totalPUnitsConverted = 0;
        uint256 totalDUnitsGranted = 0;
        
        for (uint256 i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            require(contributor != address(0), "Invalid contributor address");
            require(pUnits[contributor] >= pUnitsToConvert, "Insufficient P units");
            
            _convertPUnitsToDebt(contributor, pUnitsToConvert, multiplier);
            
            // Track totals for batch event
            uint256 dUnitsGranted = pUnitsToConvert * multiplier;
            totalPUnitsConverted += pUnitsToConvert;
            totalDUnitsGranted += dUnitsGranted;
        }
    }

    /**
    * @dev Convert ALL P units to D units for contributors
    * @param contributors Array of contributor addresses
    * @param multiplier Conversion multiplier (P units * multiplier = D units)
    */
    function convertAllPUnitsToDebt(
        address[] calldata contributors, 
        uint256 multiplier
    ) external onlyPayrollManager {
        require(contributors.length > 0, "No contributors specified");
        require(multiplier > 0, "Multiplier must be greater than 0");
        
        uint256 totalPUnitsConverted = 0;
        uint256 totalDUnitsGranted = 0;
        
        for (uint256 i = 0; i < contributors.length; i++) {
            address contributor = contributors[i];
            require(contributor != address(0), "Invalid contributor address");
            
            uint256 contributorPUnits = pUnits[contributor];
            
            // Skip contributors with no P units
            if (contributorPUnits == 0) {
                continue;
            }
            
            // Convert all P units for this contributor
            _convertPUnitsToDebt(contributor, contributorPUnits, multiplier);
            
            // Track totals for batch event
            uint256 dUnitsGranted = contributorPUnits * multiplier;
            totalPUnitsConverted += contributorPUnits;
            totalDUnitsGranted += dUnitsGranted;
        }
    }

    /**
    * @dev Internal function to convert P units to D units (no access control)
    * @param contributor Address of the contributor
    * @param pUnitsToConvert Amount of P units to convert
    * @param multiplier Conversion multiplier
    */
    function _convertPUnitsToDebt(
        address contributor,
        uint256 pUnitsToConvert,
        uint256 multiplier
    ) internal {
        // Calculate D units to grant
        uint256 dUnitsToGrant = pUnitsToConvert * multiplier;
        
        // Update balances
        pUnits[contributor] -= pUnitsToConvert;
        dUnits[contributor] += dUnitsToGrant;
        
        // Emit event
        emit PUnitsConvertedToDebt(
            contributor, 
            pUnitsToConvert, 
            dUnitsToGrant, 
            multiplier, 
            block.timestamp
        );
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
    
    // Replace your current functions with these:

    function executePUnitPayout() external onlyPayrollManager nonReentrant {
        _executePUnitPayoutInternal(type(uint256).max);
    }

    function executePUnitPayoutAmount(uint256 distributionAmount) external onlyPayrollManager nonReentrant {
        _executePUnitPayoutInternal(distributionAmount);
    }

    function _executePUnitPayoutInternal(uint256 distributionAmount) internal {
        require(contributorList.length > 0, "No contributors to distribute to");
        
        // Calculate total P-Units from active contributors
        (uint256 totalActivePUnits, uint256 activeContributorCount) = _calculateTotalActivePUnits();
        
        require(activeContributorCount > 0, "No active contributors");
        require(totalActivePUnits > 0, "No P-Units to distribute");
        require(payrollPool > 0, "No funds available");
        
        // Determine distribution amount - use all funds if amount is maxed out
        uint256 targetDistributionAmount = distributionAmount == type(uint256).max 
            ? payrollPool 
            : distributionAmount;
        
        require(targetDistributionAmount > 0, "Distribution amount must be greater than 0");
        require(targetDistributionAmount <= payrollPool, "Distribution amount exceeds available funds");
        
        // Determine how much we can actually pay out
        uint256 maxAffordablePUnits = _normalizeToInternal(targetDistributionAmount, paymentUnitDecimals);
        uint256 pUnitsToDistribute = totalActivePUnits <= maxAffordablePUnits 
            ? totalActivePUnits 
            : maxAffordablePUnits;
        uint256 totalTokensToDistribute = _normalizeToToken(pUnitsToDistribute, paymentUnitDecimals);
        
        // Verify sufficient balance
        require(paymentUnit.balanceOf(address(this)) >= totalTokensToDistribute, "Insufficient token balance");
        
        _logDistributionDetails(maxAffordablePUnits, totalActivePUnits, activeContributorCount, pUnitsToDistribute, totalTokensToDistribute);
        
        // Execute the distribution
        uint256 totalTokensDistributed = _distributeToContributors(pUnitsToDistribute, totalActivePUnits, totalTokensToDistribute);
        
        // Update contract state
        _updateContractState(totalTokensToDistribute);
        
        emit DistributionExecuted(distributionCounter, pUnitsToDistribute, 0);
    }

    function _calculateTotalActivePUnits() private view returns (uint256 totalPUnits, uint256 activeCount) {
        for (uint i = 0; i < contributorList.length; i++) {
            uint256 contributorPUnits = pUnits[contributorList[i]];
            if (contributorPUnits > 0) {
                totalPUnits += contributorPUnits;
                activeCount++;
            }
        }
    }

    function _distributeToContributors(
        uint256 pUnitsToDistribute, 
        uint256 totalActivePUnits, 
        uint256 totalTokensToDistribute
    ) private returns (uint256 totalTokensDistributed) {
        address firstActiveContributor = address(0);
        uint8 tokenDecimals = paymentUnitDecimals; 
        
        // Process all contributors except the first active one
        for (uint i = 0; i < contributorList.length; i++) {
            address contributor = contributorList[i];
            uint256 contributorPUnits = pUnits[contributor];
            
            if (contributorPUnits > 0) {
                // Calculate this contributor's share in internal decimals
                uint256 pUnitShareToDeduct = (contributorPUnits * pUnitsToDistribute) / totalActivePUnits;
                uint256 tokenAmountToTransfer = _normalizeToToken(pUnitShareToDeduct, tokenDecimals);
                
                if (firstActiveContributor == address(0)) {
                    // Save first active contributor for rounding adjustment
                    firstActiveContributor = contributor;
                    console.log("First active contributor:", firstActiveContributor);
                } else {
                    // Distribute to all other contributors
                    if (tokenAmountToTransfer > 0) {
                         console.log("Distributing to:", contributor, "Amount:", tokenAmountToTransfer);
                        paymentUnit.safeTransfer(contributor, tokenAmountToTransfer);
                        totalTokensDistributed += tokenAmountToTransfer;
                        
                        console.log("Reducing P Unit balance:", pUnits[contributor], "by", pUnitShareToDeduct);
                        pUnits[contributor] -= pUnitShareToDeduct;
                        console.log("New P Unit balance:", pUnits[contributor]);
                    }
                }
                
                emit PaymentProcessed(contributor, pUnitShareToDeduct, 0, pUnitShareToDeduct);
            }
        }
        
        // Handle first active contributor with remaining amount (includes rounding dust)
        if (firstActiveContributor != address(0)) {
            uint256 remainingTokenAmount = totalTokensToDistribute - totalTokensDistributed;
            if (remainingTokenAmount > 0) {
                console.log("Distributing remaining to:", firstActiveContributor, "Amount:", remainingTokenAmount);
                paymentUnit.safeTransfer(firstActiveContributor, remainingTokenAmount);
                
                // BUG FIX: Convert remaining token amount back to internal decimals before deducting
                uint256 remainingPUnitsToDeduct = _normalizeToInternal(remainingTokenAmount, tokenDecimals);
                console.log("Reducing P Unit balance:", pUnits[firstActiveContributor], "by", remainingPUnitsToDeduct);
                pUnits[firstActiveContributor] -= remainingPUnitsToDeduct;
                console.log("New P Unit balance:", pUnits[firstActiveContributor]);
            }
        }
        
        return totalTokensDistributed;
    }

    function _updateContractState(uint256 totalTokensDistributed) private {
        payrollPool -= totalTokensDistributed;
        distributionCounter++;
        distributionTimestamps[distributionCounter] = block.timestamp;
    }

    function _logDistributionDetails(
        uint256 maxAffordablePUnits, 
        uint256 totalActivePUnits, 
        uint256 activeContributorCount, 
        uint256 pUnitsToDistribute,
        uint256 totalTokensToDistribute
    ) private view {
        uint8 tokenDecimals = paymentUnitDecimals; 
        console.log("token balance", paymentUnit.balanceOf(address(this)));
        console.log("maxAffordablePUnits", maxAffordablePUnits);
        console.log("pUnitsToDistribute", pUnitsToDistribute);
        console.log("totalTokensToDistribute", totalTokensToDistribute);
        console.log("totalTokenAmount", _normalizeToToken(pUnitsToDistribute, tokenDecimals));
        console.log("totalActivePUnits:", totalActivePUnits);
        console.log("Active Contributors:", activeContributorCount);
        console.log("contributorList.length:", contributorList.length);
        console.log("Payroll Pool:", payrollPool);
        console.log("Token Decimals:", tokenDecimals);
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
    
    function setProjectLead(address _newLead) external onlyProjectLead {
        require(_newLead != address(0), "Invalid address");
        projectLead = _newLead;
    }
    
    function setPayrollManager(address _newManager) external onlyPayrollManager {
        require(_newManager != address(0), "Invalid address");
        payrollManager = _newManager;
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

    function getPUnitEarned(address contributor) external view returns (uint256){
        return pUnits[contributor];
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