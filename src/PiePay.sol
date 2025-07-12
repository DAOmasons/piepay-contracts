// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

enum UnitType {
    Profit,   // P-Units - decrement on payout
    Debt,     // D-Units - decrement on payout  
    Capital   // C-Units - persist on payout (dividend-like)
}

enum ContributionStatus {
    None,     // Default state
    Pending,  // Submitted and awaiting review
    Approved, // Approved by project lead
    Rejected  // Rejected by project lead
}

contract PiePay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ STATE VARIABLES ============
    
    IERC20 public immutable paymentToken;
    uint8 public immutable paymentTokenDecimals; //Use payment token decimals for unit precision as well
    
    address public projectLead; // Consider this could be an external contract
    address public payrollManager; // This too
    
    // Independent conversion multipliers (basis points: 10000 = 1.0x)
    uint16 public pToDMultiplier = 15000; // P→D: 1.5x (50% bonus for risk)
    uint16 public pToCMultiplier = 3000;  // P→C: 0.3x (need ~3.33 P-Units per C-Unit)
    uint16 public dToCMultiplier = 2000;  // D→C: 0.2x (need 5 D-Units per C-Unit)
    
    uint256 public payrollPool; //How much money is available for payroll payouts
    
    // Contributor whitelist and tracking
    mapping(address => bool) public whitelistedContributors; //mapping of current whitelisted contributors
    address[] public contributorList; //Array of all contributors, past and present, so they can be paid even if removed from whitelist
    
    // Each contributor's unit balances for P-Units, D-Units, and C-Units
    mapping(address => mapping(uint8 => uint256)) public unitBalances; //user => unitType => balance 
    mapping(uint8 => address[]) public unitHolders; // Unit holder arrays for efficient payout iteration
    
    // Total units outstanding by type for gas-efficient reads
    mapping(uint8 => uint256) public totalUnitsOutstanding;
    
    // Capacity tracking for conversions (only applies to D and C units)
    mapping(uint8 => uint256) public unitTypeCapacity;   // Maximum convertible units by type
    mapping(uint8 => uint256) public unitTypeAllocated;  // Currently allocated units by type
    

    // Contribution tracking
    mapping(uint256 => ContributionReport) public contributions;
    uint256 public contributionCounter; // Used as a pointer to the next empty contribution slot in contributions array
    struct ContributionReport {
        address contributor;
        UnitType unitType;
        uint256 unitsRequested;
        ContributionStatus status;
        string description;
    }

    // ============ NEW STRUCTS FOR PAYOUT LOGIC ============
    
    struct PayoutState {
        uint256 totalUnits;
        uint256 actualDistributionAmount;
        uint256 totalDistributed;
        address firstHolder;
        uint256 firstHolderIndex;
        uint256 recipientCount;
    }
    

    // ============ EVENTS ============
    
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
    event TotalUnitsUpdated(UnitType indexed unitType, uint256 newTotal);
    event ConversionMultipliersUpdated(address indexed executor, uint16 pToDMultiplier, uint16 pToCMultiplier, uint16 dToCMultiplier);
    event UnitCapacityUpdated(address indexed executor, UnitType indexed unitType, uint256 newCapacity);

    // ============ TOTAL UNITS TRACKING ============
    
    /**
     * @notice Updates total units outstanding for a unit type
     * @param unitType The type of units being updated
     * @param change The change in units (can be positive or negative)
     */
    function _updateTotalUnits(UnitType unitType, int256 change) private {
        uint8 unitTypeIndex = uint8(unitType);
        uint256 currentTotal = totalUnitsOutstanding[unitTypeIndex];
        uint256 newTotal;
        
        if (change >= 0) {
            newTotal = currentTotal + uint256(change);
        } else {
            uint256 decrease = uint256(-change);
            require(currentTotal >= decrease, "Total units underflow");
            newTotal = currentTotal - decrease;
        }
        
        totalUnitsOutstanding[unitTypeIndex] = newTotal;
        emit TotalUnitsUpdated(unitType, fromInternalUnits(newTotal));
    }

    // ============ DECIMAL UTILITIES ============

    /**
     * @notice Converts human-readable amount to token precision
     * @param _amount Amount in human-readable units (e.g., 100 for 100 tokens)
     * @return Amount in token precision (e.g., 100000000 for 100 USDC)
     */
    function toTokenPrecision(uint256 _amount) public view returns (uint256) {
        require(_amount <= type(uint256).max / (10 ** paymentTokenDecimals), "toTokenPrecision: overflow");
        return _amount * (10 ** paymentTokenDecimals);
    }

    /**
     * @notice Converts token precision amount to human-readable format
     * @param _amount Amount in token precision
     * @return Amount in human-readable units
     */
    function fromTokenPrecision(uint256 _amount) public view returns (uint256) {
        return _amount / (10 ** paymentTokenDecimals);
    }

    /**
     * @notice Converts 4-decimal unit amount to internal token precision
     * @param _userUnits Amount in 4-decimal format (e.g., 10000 for 1.0000 units)
     * @return Amount in internal token precision
     */
    function toInternalUnits(uint256 _userUnits) public view returns (uint256) {
        require(_userUnits <= type(uint256).max / (10 ** paymentTokenDecimals), "toInternalUnits: overflow");
        return _userUnits * (10 ** paymentTokenDecimals) / 10000;
    }

    /**
     * @notice Converts internal token precision to 4-decimal unit format
     * @param _internalUnits Amount in internal token precision
     * @return Amount in 4-decimal format
     */
    function fromInternalUnits(uint256 _internalUnits) public view returns (uint256) {
        require(_internalUnits <= type(uint256).max / 10000, "fromInternalUnits: overflow");
        // Use higher precision arithmetic to minimize rounding loss
        uint256 result = (_internalUnits * 10000 + (10 ** paymentTokenDecimals) / 2) / (10 ** paymentTokenDecimals);
        return result;
    }

    // ============ MODIFIERS ============
    
    modifier onlyProjectLead() {
        _checkProjectLead();
        _;
    }
    
    modifier onlyPayrollManager() {
        _checkPayrollManager();
        _;
    }
    
    modifier onlyWhitelistedContributor() {
        _checkWhitelistedContributor();
        _;
    }

    // ============ CONSTRUCTOR ============
    
    constructor(
        string memory _projectName,
        string memory _projectDescription,
        address _projectLead,
        address _payrollManager,
        address[] memory _initialContributors,
        address _paymentToken
    ) {
        require(_projectLead != address(0), "Invalid project lead address");
        require(_payrollManager != address(0), "Invalid payroll manager address");
        require(_paymentToken != address(0), "Invalid payment token address");
        
        projectLead = _projectLead;
        payrollManager = _payrollManager;
        paymentToken = IERC20(_paymentToken);
        paymentTokenDecimals = IERC20Metadata(_paymentToken).decimals();
        
        // Whitelist initial contributors
        for (uint256 i = 0; i < _initialContributors.length; i++) {
            _whitelistContributor(_initialContributors[i]);
        }
        
        emit ProjectInitialized(_projectName, _projectDescription, msg.sender);
    }

    // ============ WHITELIST MANAGEMENT ============
    
    function whitelistContributor(address _contributor) external onlyProjectLead {
        require(_contributor != address(0), "Invalid contributor address");
        require(_contributor != address(this), "Cannot whitelist contract itself");
        _whitelistContributor(_contributor);
    }
    
    function _whitelistContributor(address _contributor) private {
        require(!whitelistedContributors[_contributor], "Already whitelisted");
        whitelistedContributors[_contributor] = true;
        contributorList.push(_contributor);
        emit ContributorWhitelisted(msg.sender, _contributor);
    }
    
    function removeContributor(address _contributor) external onlyProjectLead {
        require(_contributor != address(0), "Invalid contributor address");
        require(whitelistedContributors[_contributor], "Not whitelisted");
        whitelistedContributors[_contributor] = false;
        // Note: Don't remove from contributorList array for historical tracking
        emit ContributorRemoved(msg.sender, _contributor);
    }

    // ============ CONTRIBUTION WORKFLOW ============
    
    function submitContribution(
        UnitType _unitType,
        uint256 _unitsRequested,
        string calldata _description
    ) external onlyWhitelistedContributor {
        require(_unitsRequested > 0, "Units requested must be greater than 0");
        require(_unitsRequested <= type(uint256).max / (10 ** paymentTokenDecimals) / 10000, "Units requested too large"); // Prevent overflow in toInternalUnits
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_description).length <= 500, "Description too long (max 500 chars)");
        require(uint8(_unitType) <= uint8(UnitType.Capital), "Invalid unit type");
        
        // Convert from 4-decimal user input to internal precision
        uint256 internalUnits = toInternalUnits(_unitsRequested);
        
        contributionCounter++;
        
        contributions[contributionCounter] = ContributionReport({
            contributor: msg.sender,
            unitType: _unitType,
            unitsRequested: internalUnits,
            status: ContributionStatus.Pending,
            description: _description
        });
        
        emit ContributionSubmitted(msg.sender, contributionCounter, _unitType, _unitsRequested, _description);
    }
    
    function reviewContribution(
        uint256 _contributionId,
        bool _approved
    ) external onlyProjectLead {
        require(_contributionId > 0 && _contributionId <= contributionCounter, "Invalid contribution ID");
        
        ContributionReport storage contribution = contributions[_contributionId];
        require(contribution.status == ContributionStatus.Pending, "Contribution already processed");
        
        if (_approved) {
            // Calculate units to award - only D-Units get multiplier
            uint256 unitsAwarded;
            if (contribution.unitType == UnitType.Debt) {
                require(contribution.unitsRequested <= type(uint256).max / pToDMultiplier, "Multiplier overflow");
                unitsAwarded = (contribution.unitsRequested * pToDMultiplier) / 10000;
            } else {
                // P-Units and C-Units: no multiplier applied
                unitsAwarded = contribution.unitsRequested;
            }
            
            // Check capacity constraints for D-Units and C-Units
            uint8 unitTypeIndex = uint8(contribution.unitType);
            if (unitTypeIndex > 0) {
                require(_hasCapacity(contribution.unitType, unitsAwarded), "Exceeds unit capacity");
            }
            
            // Update contributor's unit balance
            uint256 previousBalance = unitBalances[contribution.contributor][unitTypeIndex];
            unitBalances[contribution.contributor][unitTypeIndex] += unitsAwarded;
            
            // Update capacity tracking for D-Units and C-Units
            if (unitTypeIndex > 0) {
                unitTypeAllocated[unitTypeIndex] += unitsAwarded;
            }
            
            // Update total units outstanding
            _updateTotalUnits(contribution.unitType, int256(unitsAwarded));
            
            // Add to unit holder tracking if first time holding this unit type
            if (previousBalance == 0) {
                _addUnitHolder(contribution.contributor, contribution.unitType);
            }
            
            contribution.status = ContributionStatus.Approved;
            
            // Convert unitsAwarded to user-facing 4-decimal format for event
            uint256 userFacingAwarded = fromInternalUnits(unitsAwarded);
            
            emit ContributionApproved(msg.sender, _contributionId, contribution.contributor, contribution.unitType, userFacingAwarded);
        } else {
            contribution.status = ContributionStatus.Rejected;
            emit ContributionRejected(msg.sender, _contributionId, contribution.contributor);
        }
    }

    // ============ UNIT CONVERSION ============
    
    /**
     * @notice Convert units from one type to another (P→D, P→C, D→C only)
     * @param fromType Source unit type
     * @param toType Target unit type  
     * @param amount Amount of source units to convert
     */
    function convertUnits(
        UnitType fromType, 
        UnitType toType, 
        uint256 amount
    ) external onlyWhitelistedContributor {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= type(uint256).max / (10 ** paymentTokenDecimals) / 10000, "Amount too large");
        require(uint8(fromType) <= uint8(UnitType.Capital), "Invalid from unit type");
        require(uint8(toType) <= uint8(UnitType.Capital), "Invalid to unit type");
        require(uint8(toType) > uint8(fromType), "Can only convert up the hierarchy");
        
        // Convert from 4-decimal user input to internal precision
        uint256 internalAmount = toInternalUnits(amount);
        
        uint8 fromIndex = uint8(fromType);
        require(unitBalances[msg.sender][fromIndex] >= internalAmount, "Insufficient source units");
        
        // Calculate conversion amount based on path
        uint256 unitsToReceive;
        if (fromType == UnitType.Profit && toType == UnitType.Debt) {
            require(internalAmount <= type(uint256).max / pToDMultiplier, "P to D conversion overflow");
            unitsToReceive = (internalAmount * pToDMultiplier) / 10000;
        } else if (fromType == UnitType.Profit && toType == UnitType.Capital) {
            require(internalAmount <= type(uint256).max / pToCMultiplier, "P to C conversion overflow");
            unitsToReceive = (internalAmount * pToCMultiplier) / 10000;
        } else if (fromType == UnitType.Debt && toType == UnitType.Capital) {
            require(internalAmount <= type(uint256).max / dToCMultiplier, "D to C conversion overflow");
            unitsToReceive = (internalAmount * dToCMultiplier) / 10000;
        } else {
            revert("Invalid conversion path");
        }
        
        // Check capacity constraints (only for D and C units)
        require(_hasCapacity(toType, unitsToReceive), "Exceeds conversion capacity");
        
        // Execute the conversion
        _executeConversion(fromType, toType, internalAmount, unitsToReceive, amount);
    }
    
    /**
     * @notice Check if there's sufficient capacity for a conversion
     * @param unitType Target unit type
     * @param amount Amount to convert
     * @return True if capacity allows the conversion
     */
    function _hasCapacity(UnitType unitType, uint256 amount) private view returns (bool) {
        uint8 typeIndex = uint8(unitType);
        // P-Units have no capacity limits (they're earned through contributions)
        if (typeIndex == 0) return true;
        
        uint256 capacity = unitTypeCapacity[typeIndex];
        // If capacity is 0, treat as unlimited
        if (capacity == 0) return true;
        
        return unitTypeAllocated[typeIndex] + amount <= capacity;
    }
    
    /**
     * @notice Execute the actual conversion between unit types
     * @param fromType Source unit type
     * @param toType Target unit type
     * @param fromAmount Amount being converted from (internal precision)
     * @param toAmount Amount being converted to (internal precision)
     * @param userFromAmount Amount being converted from (user-facing 4-decimal)
     */
    function _executeConversion(
        UnitType fromType, 
        UnitType toType, 
        uint256 fromAmount, 
        uint256 toAmount,
        uint256 userFromAmount
    ) private {
        uint8 fromIndex = uint8(fromType);
        uint8 toIndex = uint8(toType);
        
        // Update balances
        unitBalances[msg.sender][fromIndex] -= fromAmount;
        uint256 previousToBalance = unitBalances[msg.sender][toIndex];
        unitBalances[msg.sender][toIndex] += toAmount;
        
        // Update totals
        _updateTotalUnits(fromType, -int256(fromAmount));
        _updateTotalUnits(toType, int256(toAmount));
        
        // Update capacity tracking (only for D and C units)
        if (toIndex > 0) {
            unitTypeAllocated[toIndex] += toAmount;
        }
        
        // Update unit holder tracking
        _updateUnitHolderTracking(msg.sender, fromType, toType, previousToBalance);
        
        // Convert toAmount to user-facing format for event
        uint256 userToAmount = fromInternalUnits(toAmount);
        
        emit UnitsConverted(msg.sender, fromType, toType, userFromAmount, userToAmount);
    }
    
    /**
     * @notice Update unit holder arrays when users convert between types
     */
    function _updateUnitHolderTracking(
        address user,
        UnitType fromType,
        UnitType toType,
        uint256 previousToBalance
    ) private {
        uint8 fromIndex = uint8(fromType);
        uint8 toIndex = uint8(toType);
        
        // Remove from source type holders if balance becomes zero
        if (unitBalances[user][fromIndex] == 0) {
            _removeUnitHolder(user, fromType);
        }
        
        // Add to target type holders if first time holding this type
        if (previousToBalance == 0) {
            _addUnitHolder(user, toType);
        }
    }

    // ============ REFACTORED PAYOUT SYSTEM ============
    
    function executeUnitPayout(
        UnitType _unitType,
        uint256 _distributionAmount
    ) external onlyPayrollManager nonReentrant {
        require(_distributionAmount > 0, "Distribution amount must be greater than 0");
        require(_distributionAmount <= payrollPool, "Distribution amount exceeds available funds");
        require(paymentToken.balanceOf(address(this)) >= _distributionAmount, "Insufficient token balance");
        require(uint8(_unitType) <= uint8(UnitType.Capital), "Invalid unit type");
        
        address[] memory holders = unitHolders[uint8(_unitType)];
        require(holders.length > 0, "No unit holders for this type");
        
        PayoutState memory state = _initializePayoutState(_unitType, _distributionAmount, holders);
        uint256[] memory distributions = _calculateDistributions(state, holders, _unitType);
        
        _updatePayrollPool(state.actualDistributionAmount);
        _executeTransfers(distributions, holders, state);
        
        emit UnitsDistributed(msg.sender, _unitType, state.actualDistributionAmount, state.recipientCount);
    }
    
    function _initializePayoutState(
        UnitType _unitType,
        uint256 _distributionAmount,
        address[] memory holders
    ) private view returns (PayoutState memory state) {
        // Calculate total units held by all holders
        {
            uint8 unitTypeIndex = uint8(_unitType);
            for (uint256 i = 0; i < holders.length; i++) {
                state.totalUnits += unitBalances[holders[i]][unitTypeIndex];
            }
        }
        require(state.totalUnits > 0, "No units to distribute");
        
        // Determine actual distribution amount
        state.actualDistributionAmount = _distributionAmount <= payrollPool ? _distributionAmount : payrollPool;
        state.firstHolder = address(0);
        state.firstHolderIndex = 0;
        state.totalDistributed = 0;
        state.recipientCount = 0;
    }
    
    function _calculateDistributions(
        PayoutState memory state,
        address[] memory holders,
        UnitType _unitType
    ) private returns (uint256[] memory distributions) {
        distributions = new uint256[](holders.length);
        uint8 unitTypeIndex = uint8(_unitType);
        
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 holderUnits = unitBalances[holder][unitTypeIndex];
            
            if (holderUnits > 0) {
                // Calculate proportional distribution with higher precision
                require(holderUnits <= type(uint256).max / state.actualDistributionAmount, "Distribution overflow");
                uint256 holderShare = (holderUnits * state.actualDistributionAmount + state.totalUnits / 2) / state.totalUnits;
                distributions[i] = holderShare;
                
                // Track first holder for rounding dust
                if (state.firstHolder == address(0)) {
                    state.firstHolder = holder;
                    state.firstHolderIndex = i;
                } else {
                    state.totalDistributed += holderShare;
                }
                
                // Update unit balances based on unit type behavior
                _updateUnitBalance(holder, holderUnits, _unitType, unitTypeIndex, state.actualDistributionAmount, state.totalUnits);
            }
        }
        
        // Give any rounding dust to the first holder
        if (state.firstHolder != address(0)) {
            distributions[state.firstHolderIndex] = state.actualDistributionAmount - state.totalDistributed;
        }
    }
    
    function _updateUnitBalance(
        address holder,
        uint256 holderUnits,
        UnitType _unitType,
        uint8 unitTypeIndex,
        uint256 actualDistributionAmount,
        uint256 totalUnits
    ) private {
        if (_unitType == UnitType.Capital) {
            // C-Units persist (dividend behavior)
            // Don't modify unit balance
        } else {
            // P-Units and D-Units decrement (buyback behavior) with higher precision
            require(holderUnits <= type(uint256).max / actualDistributionAmount, "Unit reduction overflow");
            uint256 unitsToReduce = (holderUnits * actualDistributionAmount + totalUnits / 2) / totalUnits;
            unitBalances[holder][unitTypeIndex] -= unitsToReduce;
            
            // Free up capacity for D-Units (not P-Units since they don't consume capacity)
            if (_unitType == UnitType.Debt) {
                unitTypeAllocated[unitTypeIndex] -= unitsToReduce;
            }
            
            // Update total units outstanding (reduce)
            _updateTotalUnits(_unitType, -int256(unitsToReduce));
            
            // Remove from holder tracking if balance becomes zero
            if (unitBalances[holder][unitTypeIndex] == 0) {
                _removeUnitHolder(holder, _unitType);
            }
        }
    }
    
    function _updatePayrollPool(uint256 actualDistributionAmount) private {
        payrollPool -= actualDistributionAmount;
    }
    
    function _executeTransfers(
        uint256[] memory distributions,
        address[] memory holders,
        PayoutState memory state
    ) private {
        for (uint256 i = 0; i < holders.length; i++) {
            if (distributions[i] > 0) {
                paymentToken.safeTransfer(holders[i], distributions[i]);
                state.recipientCount++;
            }
        }
    }
    
    function fundPayroll(uint256 _amount) external onlyPayrollManager {
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount <= type(uint128).max, "Amount exceeds maximum safe value");
        
        paymentToken.safeTransferFrom(msg.sender, address(this), _amount);
        payrollPool += _amount;
        
        emit PayrollFunded(msg.sender, _amount);
    }

    // ============ ADMINISTRATIVE FUNCTIONS ============
    
    function setConversionMultipliers(
        uint16 _pToDMultiplier,
        uint16 _pToCMultiplier, 
        uint16 _dToCMultiplier
    ) external onlyPayrollManager {
        require(_pToDMultiplier > 0 && _pToCMultiplier > 0 && _dToCMultiplier > 0, "Multipliers must be > 0");
        require(_pToDMultiplier <= type(uint16).max, "P to D multiplier too high");
        require(_pToCMultiplier <= type(uint16).max, "P to C multiplier too high");
        require(_dToCMultiplier <= type(uint16).max, "D to C multiplier too high");
        
        pToDMultiplier = _pToDMultiplier;
        pToCMultiplier = _pToCMultiplier;
        dToCMultiplier = _dToCMultiplier;
        
        emit ConversionMultipliersUpdated(msg.sender, _pToDMultiplier, _pToCMultiplier, _dToCMultiplier);
    }
    
    function setUnitCapacity(UnitType unitType, uint256 newCapacity) external onlyPayrollManager {
        require(uint8(unitType) > 0, "Cannot set capacity for P-Units"); // Only D and C units
        require(newCapacity <= type(uint256).max / (10 ** paymentTokenDecimals) / 10000, "Capacity too large"); // Prevent overflow
        
        // Convert from 4-decimal user input to internal precision
        uint256 internalCapacity = toInternalUnits(newCapacity);
        
        unitTypeCapacity[uint8(unitType)] = internalCapacity;
        emit UnitCapacityUpdated(msg.sender, unitType, newCapacity);
    }
    
    function setProjectLead(address _newLead) external onlyProjectLead {
        require(_newLead != address(0), "Invalid address");
        require(_newLead != address(this), "Cannot set contract as project lead");
        require(_newLead != projectLead, "New lead same as current lead");
        projectLead = _newLead;
        emit ProjectLeadUpdated(msg.sender, _newLead);
    }
    
    function setPayrollManager(address _newManager) external onlyPayrollManager {
        require(_newManager != address(0), "Invalid address");
        require(_newManager != address(this), "Cannot set contract as payroll manager");
        require(_newManager != payrollManager, "New manager same as current manager");
        payrollManager = _newManager;
        emit PayrollManagerUpdated(msg.sender, _newManager);
    }

    // ============ VIEW FUNCTIONS ============
    
    function getContributorUnits(address _contributor) external view returns (
        uint256 profitUnits,
        uint256 debtUnits,
        uint256 capitalUnits
    ) {
        return (
            fromInternalUnits(unitBalances[_contributor][uint8(UnitType.Profit)]),
            fromInternalUnits(unitBalances[_contributor][uint8(UnitType.Debt)]),
            fromInternalUnits(unitBalances[_contributor][uint8(UnitType.Capital)])
        );
    }
    
    function getUnitHolders(UnitType _unitType) external view returns (address[] memory) {
        return unitHolders[uint8(_unitType)];
    }
    
    function getTotalUnitsOutstanding(UnitType _unitType) external view returns (uint256) {
        return fromInternalUnits(totalUnitsOutstanding[uint8(_unitType)]);
    }
    
    function getContributionDetails(uint256 _contributionId) external view returns (ContributionReport memory) {
        require(_contributionId > 0 && _contributionId <= contributionCounter, "Invalid contribution ID");
        ContributionReport memory report = contributions[_contributionId];
        // Convert unitsRequested to user-facing 4-decimal format
        report.unitsRequested = fromInternalUnits(report.unitsRequested);
        return report;
    }
    
    function getContributorCount() external view returns (uint256) {
        return contributorList.length;
    }

    // ============ INTERNAL HELPER FUNCTIONS ============
    
    function _addUnitHolder(address _holder, UnitType _unitType) internal {
        uint8 unitTypeIndex = uint8(_unitType);
        address[] storage holders = unitHolders[unitTypeIndex];
        
        // Check if already in array
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == _holder) {
                return; // Already in array
            }
        }
        
        // Add to array
        holders.push(_holder);
    }
    
    function _removeUnitHolder(address _holder, UnitType _unitType) internal {
        uint8 unitTypeIndex = uint8(_unitType);
        address[] storage holders = unitHolders[unitTypeIndex];
        
        // Find and remove holder
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == _holder) {
                // Swap with last element and pop
                holders[i] = holders[holders.length - 1];
                holders.pop();
                break;
            }
        }
    }
    
    function _isUnitHolder(address _holder, UnitType _unitType) internal view returns (bool) {
        address[] memory holders = unitHolders[uint8(_unitType)];
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == _holder) {
                return true;
            }
        }
        return false;
    }

    // ============ ACCESS CONTROL ============
    
    function _checkProjectLead() internal view {
        require(msg.sender == projectLead, "Not the project lead");
    }
    
    function _checkPayrollManager() internal view {
        require(msg.sender == payrollManager, "Not the payroll manager");
    }
    
    function _checkWhitelistedContributor() internal view {
        require(whitelistedContributors[msg.sender], "Not a whitelisted contributor");
    }
}