// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title PiePay2
 * @dev Generic unit-based compensation system for teams
 * Supports three unit types: Profit Units (P), Debt Units (D), and Capital Units (C)
 */
contract PiePay2 is ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable paymentToken;
    uint8 public immutable paymentTokenDecimals;

    // Unit Types
    enum UnitType { P_UNITS, D_UNITS, C_UNITS }
    
    // Unit Configuration
    struct UnitConfig {
        uint256 purchasePrice;   // Price to purchase one unit (0 = not purchasable)
        bool isConsumable;       // true = depleted on distribution, false = permanent
        bool canBePurchased;     // true = can be purchased by authorized users
    }
    
    // Project State
    string public projectName;
    string public projectDescription;
    
    // Unit System
    mapping(UnitType => mapping(address => uint256)) public units;
    mapping(UnitType => address[]) public unitHolders;
    mapping(UnitType => mapping(address => bool)) public isUnitHolder;
    mapping(UnitType => UnitConfig) public unitConfigs;
    
    // Permission System
    mapping(bytes32 => mapping(address => bool)) public permissions;
    
    // C-Unit Purchase Allowances
    mapping(address => uint256) public cUnitPurchaseAllowance;
    
    // Treasury
    uint256 public treasuryBalance;
    
    // Permission Constants
    bytes32 public constant GRANT_P_UNITS = keccak256("GRANT_P_UNITS");
    bytes32 public constant GRANT_D_UNITS = keccak256("GRANT_D_UNITS");
    bytes32 public constant GRANT_C_UNITS = keccak256("GRANT_C_UNITS");
    bytes32 public constant PURCHASE_C_UNITS = keccak256("PURCHASE_C_UNITS");
    bytes32 public constant DISTRIBUTE_UNITS = keccak256("DISTRIBUTE_UNITS");
    bytes32 public constant MANAGE_PERMISSIONS = keccak256("MANAGE_PERMISSIONS");
    bytes32 public constant SET_C_UNIT_ALLOWANCE = keccak256("SET_C_UNIT_ALLOWANCE");
    bytes32 public constant MANAGE_TREASURY = keccak256("MANAGE_TREASURY");
    
    // Events
    event ProjectInitialized(string name, string description);
    event UnitsGranted(UnitType indexed unitType, address indexed recipient, uint256 amount, string reason, uint256 timestamp);
    event UnitsPurchased(UnitType indexed unitType, address indexed purchaser, uint256 amount, uint256 cost, uint256 timestamp);
    event UnitsDistributed(UnitType indexed unitType, uint256 totalUnitsProcessed, uint256 totalTokensDistributed, uint256 timestamp);
    event UnitsPaidOut(UnitType indexed unitType, address indexed recipient, uint256 unitsProcessed, uint256 tokenAmount, uint256 timestamp);
    event PermissionGranted(bytes32 indexed action, address indexed user);
    event PermissionRevoked(bytes32 indexed action, address indexed user);
    event CUnitPurchaseAllowanceSet(address indexed user, uint256 allowance);
    event TreasuryFunded(uint256 amount);
    event TreasuryWithdrawn(address indexed recipient, uint256 amount);
    event ZeroBalanceHoldersCleanedUp(UnitType indexed unitType, uint256 addressesRemoved);

    // Modifiers
    modifier requiresPermission(bytes32 action) {
        require(hasPermission(action, msg.sender), "Insufficient permission");
        _;
    }
    
    constructor(
        string memory _projectName,
        string memory _projectDescription,
        address _admin,
        address _paymentToken
    ) {
        projectName = _projectName;
        projectDescription = _projectDescription;
        
        paymentToken = IERC20(_paymentToken);
        paymentTokenDecimals = IERC20Metadata(_paymentToken).decimals();

        // Initialize unit configurations
        unitConfigs[UnitType.P_UNITS] = UnitConfig({
            purchasePrice: 0,           // P-Units cannot be purchased
            isConsumable: true,         // P-Units are depleted on distribution
            canBePurchased: false       // P-Units are earned, not bought
        });
        
        unitConfigs[UnitType.D_UNITS] = UnitConfig({
            purchasePrice: _normalizeToTokenAmount(1), // $1 per D-Unit
            isConsumable: true,         // D-Units are depleted on distribution
            canBePurchased: true        // D-Units can be purchased
        });
        
        unitConfigs[UnitType.C_UNITS] = UnitConfig({
            purchasePrice: _normalizeToTokenAmount(5), // $5 per C-Unit
            isConsumable: false,        // C-Units are permanent
            canBePurchased: true        // C-Units can be purchased (with allowance)
        });
        
        // Grant all permissions to admin initially
        permissions[GRANT_P_UNITS][_admin] = true;
        permissions[GRANT_D_UNITS][_admin] = true;
        permissions[GRANT_C_UNITS][_admin] = true;
        permissions[DISTRIBUTE_UNITS][_admin] = true;
        permissions[MANAGE_PERMISSIONS][_admin] = true;
        permissions[SET_C_UNIT_ALLOWANCE][_admin] = true;
        permissions[MANAGE_TREASURY][_admin] = true;
        
        emit ProjectInitialized(_projectName, _projectDescription);
    }
    
    // ============ PERMISSION MANAGEMENT ============
    
    function hasPermission(bytes32 action, address user) public view returns (bool) {
        return permissions[action][user];
    }
    
    function grantPermission(bytes32 action, address user) external requiresPermission(MANAGE_PERMISSIONS) {
        permissions[action][user] = true;
        emit PermissionGranted(action, user);
    }
    
    function revokePermission(bytes32 action, address user) external requiresPermission(MANAGE_PERMISSIONS) {
        permissions[action][user] = false;
        emit PermissionRevoked(action, user);
    }
    
    // ============ UNIT MANAGEMENT ============
    
    function grantUnits(
        UnitType unitType,
        address recipient,
        uint256 amount,
        string calldata reason
    ) external requiresPermission(_getGrantPermission(unitType)) {
        require(amount > 0, "Amount must be greater than 0");
        require(bytes(reason).length > 0, "Reason cannot be empty");
        
        _addUnits(unitType, recipient, amount);
        
        emit UnitsGranted(unitType, recipient, amount, reason, block.timestamp);
    }
    
    function purchaseUnits(UnitType unitType, uint256 amount) external {
        require(unitConfigs[unitType].canBePurchased, "Unit type not purchasable");
        require(amount > 0, "Amount must be greater than 0");
        
        if (unitType == UnitType.C_UNITS) {
            require(hasPermission(PURCHASE_C_UNITS, msg.sender), "Not authorized to purchase C-Units");
            require(cUnitPurchaseAllowance[msg.sender] >= amount, "Exceeds purchase allowance");
            cUnitPurchaseAllowance[msg.sender] -= amount;
        }
        
        uint256 cost = amount * unitConfigs[unitType].purchasePrice;
        paymentToken.safeTransferFrom(msg.sender, address(this), cost);
        treasuryBalance += cost;
        
        _addUnits(unitType, msg.sender, amount);
        
        emit UnitsPurchased(unitType, msg.sender, amount, cost, block.timestamp);
    }
    
    function setCUnitPurchaseAllowance(address user, uint256 allowance) external requiresPermission(SET_C_UNIT_ALLOWANCE) {
        cUnitPurchaseAllowance[user] = allowance;
        emit CUnitPurchaseAllowanceSet(user, allowance);
    }
    
    // ============ DISTRIBUTION SYSTEM ============
    
    function distributeUnits(UnitType unitType) external requiresPermission(DISTRIBUTE_UNITS) nonReentrant {
        _distributeUnits(unitType, type(uint256).max);
    }
    
    function distributeUnitsAmount(UnitType unitType, uint256 maxAmount) external requiresPermission(DISTRIBUTE_UNITS) nonReentrant {
        _distributeUnits(unitType, maxAmount);
    }
    
    function distributeWaterfall(uint256 totalAmount) external requiresPermission(DISTRIBUTE_UNITS) nonReentrant {
        require(totalAmount > 0, "Amount must be greater than 0");
        require(totalAmount <= treasuryBalance, "Amount exceeds treasury balance");
        
        uint256 remaining = totalAmount;
        
        // P-Units first (work compensation)
        remaining = _distributeUnits(UnitType.P_UNITS, remaining);
        if (remaining == 0) return;
        
        // D-Units second (debt repayment)
        remaining = _distributeUnits(UnitType.D_UNITS, remaining);
        if (remaining == 0) return;
        
        // C-Units last (profit sharing)
        _distributeUnits(UnitType.C_UNITS, remaining);
    }
    
    // ============ TREASURY MANAGEMENT ============
    
    function fundTreasury(uint256 amount) external requiresPermission(MANAGE_TREASURY) {
        require(amount > 0, "Amount must be greater than 0");
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        treasuryBalance += amount;
        emit TreasuryFunded(amount);
    }
    
    function withdrawFromTreasury(address recipient, uint256 amount) external requiresPermission(MANAGE_TREASURY) {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= treasuryBalance, "Insufficient treasury balance");
        require(recipient != address(0), "Invalid recipient");
        
        treasuryBalance -= amount;
        paymentToken.safeTransfer(recipient, amount);
        emit TreasuryWithdrawn(recipient, amount);
    }
    
    // ============ MAINTENANCE ============
    
    function cleanupZeroBalanceHolders(UnitType unitType) external {
        address[] storage holders = unitHolders[unitType];
        uint256 removedCount = 0;
        
        for (uint256 i = 0; i < holders.length; ) {
            if (units[unitType][holders[i]] == 0) {
                isUnitHolder[unitType][holders[i]] = false;
                holders[i] = holders[holders.length - 1];
                holders.pop();
                removedCount++;
            } else {
                i++;
            }
        }
        
        emit ZeroBalanceHoldersCleanedUp(unitType, removedCount);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function getUnitBalance(UnitType unitType, address holder) external view returns (uint256) {
        return units[unitType][holder];
    }
    
    function getUnitHolders(UnitType unitType) external view returns (address[] memory) {
        return unitHolders[unitType];
    }
    
    function getUnitHolderCount(UnitType unitType) external view returns (uint256) {
        return unitHolders[unitType].length;
    }
    
    function getTotalUnits(UnitType unitType) external view returns (uint256 total) {
        address[] memory holders = unitHolders[unitType];
        for (uint256 i = 0; i < holders.length; i++) {
            total += units[unitType][holders[i]];
        }
    }
    
    function getUnitBalances(address holder) external view returns (
        uint256 pUnits,
        uint256 dUnits,
        uint256 cUnits
    ) {
        return (
            units[UnitType.P_UNITS][holder],
            units[UnitType.D_UNITS][holder],
            units[UnitType.C_UNITS][holder]
        );
    }
    
    function getDistributionInfo() external view returns (
        uint256 totalPUnits,
        uint256 totalDUnits,
        uint256 totalCUnits,
        uint256 availableFunds
    ) {
        totalPUnits = this.getTotalUnits(UnitType.P_UNITS);
        totalDUnits = this.getTotalUnits(UnitType.D_UNITS);
        totalCUnits = this.getTotalUnits(UnitType.C_UNITS);
        availableFunds = treasuryBalance;
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    function _addUnits(UnitType unitType, address recipient, uint256 amount) internal {
        units[unitType][recipient] += amount;
        
        if (!isUnitHolder[unitType][recipient]) {
            isUnitHolder[unitType][recipient] = true;
            unitHolders[unitType].push(recipient);
        }
    }
    
    function _distributeUnits(UnitType unitType, uint256 maxAmount) internal returns (uint256 remaining) {
        address[] memory holders = unitHolders[unitType];
        require(holders.length > 0, "No unit holders to distribute to");
        require(treasuryBalance > 0, "No funds available");
        
        (uint256 totalActiveUnits, uint256 activeHolderCount) = _calculateTotalActiveUnits(unitType);
        require(activeHolderCount > 0, "No active unit holders");
        require(totalActiveUnits > 0, "No units to distribute");
        
        uint256 targetDistributionAmount = maxAmount == type(uint256).max ? treasuryBalance : maxAmount;
        require(targetDistributionAmount > 0, "Distribution amount must be greater than 0");
        require(targetDistributionAmount <= treasuryBalance, "Distribution amount exceeds treasury balance");
        
        uint256 maxAffordableUnits = _normalizeToInternal(targetDistributionAmount, paymentTokenDecimals);
        uint256 unitsToDistribute = totalActiveUnits <= maxAffordableUnits ? totalActiveUnits : maxAffordableUnits;
        uint256 totalTokensToDistribute = _normalizeToToken(unitsToDistribute, paymentTokenDecimals);
        
        require(paymentToken.balanceOf(address(this)) >= totalTokensToDistribute, "Insufficient token balance");
        
        uint256 totalTokensDistributed = _executeDistribution(unitType, unitsToDistribute, totalActiveUnits, totalTokensToDistribute);
        
        treasuryBalance -= totalTokensDistributed;
        
        emit UnitsDistributed(unitType, unitsToDistribute, totalTokensDistributed, block.timestamp);
        
        return targetDistributionAmount - totalTokensDistributed;
    }
    
    function _calculateTotalActiveUnits(UnitType unitType) internal view returns (uint256 totalUnits, uint256 activeCount) {
        address[] memory holders = unitHolders[unitType];
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 holderUnits = units[unitType][holders[i]];
            if (holderUnits > 0) {
                totalUnits += holderUnits;
                activeCount++;
            }
        }
    }
    
    function _executeDistribution(
        UnitType unitType,
        uint256 unitsToDistribute,
        uint256 totalActiveUnits,
        uint256 totalTokensToDistribute
    ) internal returns (uint256 totalTokensDistributed) {
        address[] memory holders = unitHolders[unitType];
        address firstActiveHolder = address(0);
        bool isConsumable = unitConfigs[unitType].isConsumable;
        
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 holderUnits = units[unitType][holder];
            
            if (holderUnits > 0) {
                uint256 unitShareToProcess = (holderUnits * unitsToDistribute) / totalActiveUnits;
                uint256 tokenAmountToTransfer = _normalizeToToken(unitShareToProcess, paymentTokenDecimals);
                
                if (firstActiveHolder == address(0)) {
                    firstActiveHolder = holder;
                } else {
                    if (tokenAmountToTransfer > 0) {
                        paymentToken.safeTransfer(holder, tokenAmountToTransfer);
                        totalTokensDistributed += tokenAmountToTransfer;
                        
                        if (isConsumable) {
                            units[unitType][holder] -= unitShareToProcess;
                        }
                    }
                }
                
                emit UnitsPaidOut(unitType, holder, unitShareToProcess, tokenAmountToTransfer, block.timestamp);
            }
        }
        
        // Handle first active holder with remaining amount (includes rounding dust)
        if (firstActiveHolder != address(0)) {
            uint256 remainingTokenAmount = totalTokensToDistribute - totalTokensDistributed;
            if (remainingTokenAmount > 0) {
                paymentToken.safeTransfer(firstActiveHolder, remainingTokenAmount);
                
                if (isConsumable) {
                    uint256 remainingUnitsToDeduct = _normalizeToInternal(remainingTokenAmount, paymentTokenDecimals);
                    units[unitType][firstActiveHolder] -= remainingUnitsToDeduct;
                }
            }
            totalTokensDistributed = totalTokensToDistribute;
        }
        
        return totalTokensDistributed;
    }
    
    function _getGrantPermission(UnitType unitType) internal pure returns (bytes32) {
        if (unitType == UnitType.P_UNITS) return GRANT_P_UNITS;
        if (unitType == UnitType.D_UNITS) return GRANT_D_UNITS;
        if (unitType == UnitType.C_UNITS) return GRANT_C_UNITS;
        revert("Invalid unit type");
    }
    
    function _normalizeToInternal(uint256 _tokenAmount, uint8 _tokenDecimals) internal pure returns (uint256) {
        if (_tokenDecimals <= 18) {
            return _tokenAmount * (10 ** (18 - _tokenDecimals));
        } else {
            return _tokenAmount / (10 ** (_tokenDecimals - 18));
        }
    }
    
    function _normalizeToToken(uint256 _internalAmount, uint8 _tokenDecimals) internal pure returns (uint256) {
        if (_tokenDecimals <= 18) {
            return _internalAmount / (10 ** (18 - _tokenDecimals));
        } else {
            return _internalAmount * (10 ** (_tokenDecimals - 18));
        }
    }
    
    function _normalizeToTokenAmount(uint256 dollarAmount) internal view returns (uint256) {
        return dollarAmount * (10 ** paymentTokenDecimals);
    }
}