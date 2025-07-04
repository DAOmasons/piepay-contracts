// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

//import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "lib/forge-std/src/console.sol";

/**
 * @title PiePay
 * @dev Manages team contributions with internal unit-based compensation
 * Based on the Gardens/PiePay proposal for fair team payouts
 * Uses internal integer accounting instead of transferable tokens
 */

// Note: We still need D&C Unit distros 
// Note: We still need conversion functions 
contract PiePay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Note: If we're going to save the token Interface here (which is good), 
    // can we not reference this contract for decimals? I think we could avoid the decimal hell found below
    // Note: I would rename to payment token
    IERC20 public immutable paymentUnit; // e.g. USDC contract

    uint8 paymentUnitDecimals;
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
        string description;
        ContributionStatus status;
        uint256 timestamp;
        address contributor;
        uint256 pUnitsClaimed; // P-Units claimed by contributor
    }
    
    //Note: No need to save these to global state, they can 
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
    
    // Note: I don't think we need to track distributions. 
    // Distribution tracking
    uint256 public distributionCounter;
    mapping(uint256 => uint256) public distributionTimestamps;
    
    // Project configuration
    uint256 public payrollPool; // Internal accounting for available funds
    
    // Constants (simple dollar values)
    // Note: These should be parameters
    // Note: These aren't yet converting 
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
    ) {
        projectName = _projectName;
        projectDescription = _projectDescription;
        projectLead = _projectLead;
        payrollManager = _payrollManager;
        
        paymentUnit = IERC20(_paymentUnit);
        paymentUnitDecimals = IERC20Metadata(address(paymentUnit)).decimals();

        // Whitelist initial contributors
        for (uint i = 0; i < _initialContributors.length; i++) {
            _whitelistContributor(_initialContributors[i]);
        }

        //Note: indexer should be able to see the payment token and other parameters (once added)
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



    // Note: Interesting issue here: 
    // If we remove a contributor from the list, does that mean they can no longer be paid? 
    // Is that what we would want? In my mind, we would want ex-listed contributors to not be able to 
    // post a contribution. But we would still want them to be rewarded for their efforts. 
    // Something to think about. 
    function removeContributor(address _contributor) external onlyProjectLead {
        require(whitelistedContributors[_contributor], "Not whitelisted");
        whitelistedContributors[_contributor] = false;
        
        // Remove from contributor list
        for (uint i = 0; i < contributorList.length; i++) {
            if (contributorList[i] == _contributor) {
                contributorList[i] = contributorList[contributorList.length - 1];

                // Note: Would this not cause that last contributor in the list to be overwritten? 
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
            description: _description,
            status: ContributionStatus.Pending,
            timestamp: block.timestamp,
            contributor: msg.sender,
            pUnitsClaimed: _pUnitsClaimed
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
    
    // Payroll Management
    function fundPayroll(uint256 _amount) external onlyPayrollManager {
        require(_amount > 0, "Amount must be greater than 0");
        // Transfer USDC from payroll manager to this contract
        paymentUnit.safeTransferFrom(msg.sender, address(this), _amount);

        // Get token decimals and convert to internal 18-decimal accounting
        // uint8 tokenDecimals = IERC20Metadata(address(paymentUnit)).decimals();
        // uint256 normalizedAmount = _normalizeToInternal(_amount, tokenDecimals);


        // I wonder if we can avoid saving a pool variable and just look up token.balanceOf(this)
        payrollPool += _amount;

        emit PayrollFunded(_amount);
    }
    

    // Note: Wasn't this supposed to parametized so that we could use it for other tokens? 
    // Note: How do we catch overflow? 
    // Note: How are debt and capital units handled?
    function executePUnitPayout() external onlyPayrollManager nonReentrant {
        require(contributorList.length > 0, "No contributors to distribute to");
        
        // Calculate total P-Units from active contributors
        (uint256 totalActivePUnits, uint256 activeContributorCount) = _calculateTotalActivePUnits();
        
        require(activeContributorCount > 0, "No active contributors");
        require(totalActivePUnits > 0, "No P-Units to distribute");
        require(payrollPool > 0, "No funds available");
        
        // Determine how much we can actually pay out
        uint256 maxAffordablePUnits = _normalizeToInternal(payrollPool, paymentUnitDecimals);
        uint256 pUnitsToDistribute = totalActivePUnits <= maxAffordablePUnits 
            ? totalActivePUnits 
            : maxAffordablePUnits;
        uint256 totalTokensToDistribute = _normalizeToToken(pUnitsToDistribute, paymentUnitDecimals);
        
        // Verify sufficient balance

        // Note: Will this check work if we're adjusting the decimal amounts?
        require(paymentUnit.balanceOf(address(this)) >= totalTokensToDistribute, "Insufficient token balance");
        
        _logDistributionDetails(maxAffordablePUnits, totalActivePUnits, activeContributorCount, pUnitsToDistribute, totalTokensToDistribute);
        
        // Execute the distribution
        _distributeToContributors(pUnitsToDistribute, totalActivePUnits, totalTokensToDistribute);
        
        // Update contract state
        _updateContractState(totalTokensToDistribute);
        
        emit DistributionExecuted(distributionCounter, pUnitsToDistribute, 0);
    }

    // Note: We should probably save this is a variable instead of calculating it every time
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
                    // Note: Will need to understand this a bit. s this to hold extra funds for rounding adjustments?
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


    // Note: Do we need to do any of this. Updating the pool amount seems good. But the rest?
    function _updateContractState(uint256 totalTokensDistributed) private {
        payrollPool -= totalTokensDistributed;
        distributionCounter++;
        distributionTimestamps[distributionCounter] = block.timestamp;
    }


    // Note: I imagine this is for debugging purposes
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

    //Note: State should be stored at the top of the contract 
    // Add this mapping to store split addresses
    mapping(uint256 => address) public distributionSplits;

    // Add this event
    // Note: What's up with this?
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

        // Note: Why not just transfer now?
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


    // Note: If this isn't being used in the contract or for testing, we can remove it. The indexer will handle this. 
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


    // Note: If this isn't being used in the contract or for testing, we can remove it. The indexer will handle this. 
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


    // Note: trying to understand what this is for. Why do we need to normalize the decimals?
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