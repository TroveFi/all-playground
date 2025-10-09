// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

interface IMorePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IPoolDataProvider {
    function getUserReserveData(address asset, address user) external view returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
    );
}

/// @title MOREMarketsStrategy - Supply & Borrow on MORE Markets
/// @notice Implements your supply-to-more.js and borrow-from-more.js logic
contract MOREMarketsStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ====================================================================
    // CONSTANTS
    // ====================================================================
    address public constant MORE_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    address public constant POOL_DATA_PROVIDER = 0x79e71e3c0EDF2B88b0aB38E9A1eF0F6a230e56bf;
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    
    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    address public vault;
    mapping(address => uint256) public suppliedAssets;
    mapping(address => uint256) public borrowedAssets;
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    event Supplied(address indexed asset, uint256 amount);
    event Withdrawn(address indexed asset, uint256 amount);
    event Borrowed(address indexed asset, uint256 amount);
    event Repaid(address indexed asset, uint256 amount);
    event Harvested(uint256 totalHarvested);
    
    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    constructor(address _vault) {
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
        _grantRole(AGENT_ROLE, msg.sender);
    }
    
    // ====================================================================
    // STRATEGY FUNCTIONS
    // ====================================================================
    
    /// @notice Execute: Supply asset to MORE Markets
    function executeWithAsset(
        address asset,
        uint256 amount,
        bytes calldata data
    ) external payable onlyRole(VAULT_ROLE) nonReentrant returns (uint256) {
        require(amount > 0, "Amount must be positive");
        
        // Decode action type
        (string memory action) = abi.decode(data, (string));
        
        if (keccak256(bytes(action)) == keccak256("supply")) {
            return _supply(asset, amount);
        } else if (keccak256(bytes(action)) == keccak256("borrow")) {
            return _borrow(asset, amount);
        } else {
            revert("Invalid action");
        }
    }
    
    function _supply(address asset, uint256 amount) internal returns (uint256) {
        // Approve MORE pool
        IERC20(asset).safeApprove(MORE_POOL, amount);
        
        // Supply to MORE
        IMorePool(MORE_POOL).supply(asset, amount, address(this), 0);
        
        suppliedAssets[asset] += amount;
        
        emit Supplied(asset, amount);
        return amount;
    }
    
    function _borrow(address asset, uint256 amount) internal returns (uint256) {
        // Borrow from MORE (variable rate = 2)
        IMorePool(MORE_POOL).borrow(asset, amount, 2, 0, address(this));
        
        borrowedAssets[asset] += amount;
        
        emit Borrowed(asset, amount);
        return amount;
    }
    
    /// @notice Agent function: Borrow assets after supplying collateral
    function borrowAsset(address asset, uint256 amount) 
        external 
        onlyRole(AGENT_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        // Check health factor before borrowing
        (, , uint256 availableBorrows, , , uint256 healthFactor) = 
            IMorePool(MORE_POOL).getUserAccountData(address(this));
        
        require(healthFactor > 1.5e18 || healthFactor == 0, "Health factor too low");
        require(availableBorrows >= amount, "Insufficient borrow capacity");
        
        IMorePool(MORE_POOL).borrow(asset, amount, 2, 0, address(this));
        borrowedAssets[asset] += amount;
        
        emit Borrowed(asset, amount);
        return amount;
    }
    
    /// @notice Agent function: Repay borrowed assets
    function repayAsset(address asset, uint256 amount) 
        external 
        onlyRole(AGENT_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        require(borrowedAssets[asset] >= amount, "Repay amount exceeds debt");
        
        IERC20(asset).safeApprove(MORE_POOL, amount);
        uint256 repaid = IMorePool(MORE_POOL).repay(asset, amount, 2, address(this));
        
        borrowedAssets[asset] -= repaid;
        
        emit Repaid(asset, repaid);
        return repaid;
    }
    
    /// @notice Harvest: Withdraw supplied assets + any accrued interest
    function harvest(bytes calldata data) 
        external 
        onlyRole(AGENT_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        address asset = abi.decode(data, (address));
        
        // Get current aToken balance
        (uint256 aTokenBalance, , , , , , , , ) = 
            IPoolDataProvider(POOL_DATA_PROVIDER).getUserReserveData(asset, address(this));
        
        if (aTokenBalance == 0) {
            return 0;
        }
        
        // Calculate harvestable amount (interest earned)
        uint256 harvestable = aTokenBalance > suppliedAssets[asset] 
            ? aTokenBalance - suppliedAssets[asset] 
            : 0;
        
        if (harvestable > 0) {
            // Withdraw only the interest
            IMorePool(MORE_POOL).withdraw(asset, harvestable, vault);
            
            emit Harvested(harvestable);
            return harvestable;
        }
        
        return 0;
    }
    
    /// @notice Emergency exit: Withdraw all supplied assets
    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        address asset = abi.decode(data, (address));
        
        // Get current aToken balance
        (uint256 aTokenBalance, , , , , , , , ) = 
            IPoolDataProvider(POOL_DATA_PROVIDER).getUserReserveData(asset, address(this));
        
        if (aTokenBalance > 0) {
            // Withdraw everything
            uint256 withdrawn = IMorePool(MORE_POOL).withdraw(asset, type(uint256).max, vault);
            suppliedAssets[asset] = 0;
            
            emit Withdrawn(asset, withdrawn);
            return withdrawn;
        }
        
        return 0;
    }
    
    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================
    function getBalance() external view returns (uint256) {
        // Return total value of supplied assets (simplified)
        return 0; // Would need to sum all aToken balances
    }
    
    function underlyingToken() external pure returns (address) {
        return address(0); // Multi-asset strategy
    }
    
    function strategyType() external pure returns (string memory) {
        return "MOREMarkets";
    }
    
    function getPositionData(address asset) external view returns (
        uint256 supplied,
        uint256 borrowed,
        uint256 healthFactor,
        uint256 availableToBorrow
    ) {
        (uint256 aTokenBalance, , uint256 variableDebt, , , , , , ) = 
            IPoolDataProvider(POOL_DATA_PROVIDER).getUserReserveData(asset, address(this));
        
        (, , uint256 availableBorrowsBase, , , uint256 hf) = 
            IMorePool(MORE_POOL).getUserAccountData(address(this));
        
        return (aTokenBalance, variableDebt, hf, availableBorrowsBase);
    }
    
    function getHealthFactor() external view returns (uint256) {
        (, , , , , uint256 healthFactor) = 
            IMorePool(MORE_POOL).getUserAccountData(address(this));
        return healthFactor;
    }
}