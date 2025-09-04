// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Real More.Markets Protocol Interfaces (Aave-style on Flow)
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
    function getPriceOracle() external view returns (address);
    function getACLManager() external view returns (address);
}

interface IPool {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    function getReserveData(address asset) external view returns (
        uint256 configuration,
        uint128 liquidityIndex,
        uint128 currentLiquidityRate,
        uint128 variableBorrowIndex,
        uint128 currentVariableBorrowRate,
        uint128 currentStableBorrowRate,
        uint40 lastUpdateTimestamp,
        uint16 id,
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        uint128 accruedToTreasury,
        uint128 unbacked,
        uint128 isolationModeTotalDebt
    );

    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IAToken is IERC20 {
    function scaledBalanceOf(address user) external view returns (uint256);
    function getScaledUserBalanceAndSupply(address user) external view returns (uint256, uint256);
    function scaledTotalSupply() external view returns (uint256);
}

/// @title MoreMarketsStrategy - Real More.Markets Integration on Flow EVM
/// @notice Strategy that deposits assets into More.Markets (Aave fork) for yield generation
/// @dev Integrates with real More.Markets protocol deployed on Flow EVM Mainnet
contract MoreMarketsStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // ROLES & CONSTANTS
    // ====================================================================

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Real More.Markets contract addresses on Flow EVM
    address public constant POOL_ADDRESSES_PROVIDER = 0x1830a96466d1d108935865c75B0a9548681Cfd9A;
    address public constant MORE_MARKETS_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================

    IERC20 public immutable assetToken;
    IERC20 public aToken; // Changed from IAToken to IERC20
    IPool public immutable pool;
    IPoolAddressesProvider public immutable poolProvider;
    
    address public vault;
    bool public strategyPaused;

    // Strategy metrics
    uint256 public totalDeployed;
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;

    // Risk and performance tracking
    uint256 public maxSlippage = 300; // 3% default
    uint256 public maxSingleDeployment = 1000000 * 10**6; // 1M USDC default
    uint256 public minHarvestAmount = 1 * 10**6; // 1 USDC minimum

    // Protocol data
    uint256 public lastRecordedLiquidityIndex;
    uint256 public lastSupplyRate;

    // ====================================================================
    // EVENTS
    // ====================================================================

    event StrategyExecuted(uint256 amount, bytes data);
    event StrategyHarvested(uint256 harvested, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount);
    event StrategyPaused();
    event StrategyUnpaused();
    event SupplyRateUpdated(uint256 newRate);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================

    constructor(
        address _asset,
        address _vault
    ) {
        require(_asset != address(0), "Invalid asset");
        require(_vault != address(0), "Invalid vault");

        assetToken = IERC20(_asset);
        vault = _vault;

        // Initialize More.Markets interfaces
        poolProvider = IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
        pool = IPool(MORE_MARKETS_POOL);

        // Get aToken for this asset
        address aTokenAddr = _getATokenAddress(_asset);
        if (aTokenAddr != address(0)) {
            aToken = IERC20(aTokenAddr); // Changed to IERC20
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    // ====================================================================
    // MODIFIERS
    // ====================================================================

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault can call");
        _;
    }

    modifier whenNotPaused() {
        require(!strategyPaused, "Strategy is paused");
        _;
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= maxSingleDeployment, "Amount exceeds max deployment");

        // Transfer tokens from vault
        assetToken.safeTransferFrom(msg.sender, address(this), amount);

        // Approve More.Markets pool
        assetToken.approve(address(pool), amount);

        // Supply to More.Markets
        pool.supply(address(assetToken), amount, address(this), 0);

        totalDeployed += amount;

        // Update liquidity index for tracking
        _updateLiquidityIndex();

        emit StrategyExecuted(amount, data);
    }

    function harvest(bytes calldata data) external onlyVault nonReentrant whenNotPaused {
        uint256 assetBalanceBefore = assetToken.balanceOf(address(this));
        
        // Get current aToken balance
        uint256 aTokenBalance = address(aToken) != address(0) ? aToken.balanceOf(address(this)) : 0;
        
        if (aTokenBalance == 0) {
            return; // Nothing to harvest
        }

        // Calculate yield (interest earned)
        uint256 currentTotalBalance = _getTotalBalance();
        uint256 yield = currentTotalBalance > totalDeployed ? currentTotalBalance - totalDeployed : 0;

        if (yield >= minHarvestAmount) {
            // Withdraw only the yield
            pool.withdraw(address(assetToken), yield, address(this));
            
            uint256 actualHarvested = assetToken.balanceOf(address(this)) - assetBalanceBefore;
            
            if (actualHarvested > 0) {
                // Transfer harvested amount to vault
                assetToken.safeTransfer(vault, actualHarvested);
                
                totalHarvested += actualHarvested;
                lastHarvestTime = block.timestamp;
                harvestCount++;
                
                emit StrategyHarvested(actualHarvested, totalHarvested);
            }
        }

        // Update metrics
        _updateLiquidityIndex();
    }

    function emergencyExit(bytes calldata data) external onlyRole(EMERGENCY_ROLE) nonReentrant {
        strategyPaused = true;

        uint256 aTokenBalance = address(aToken) != address(0) ? aToken.balanceOf(address(this)) : 0;
        uint256 recovered = 0;

        if (aTokenBalance > 0) {
            try pool.withdraw(address(assetToken), type(uint256).max, address(this)) returns (uint256 withdrawnAmount) {
                recovered = withdrawnAmount;
            } catch {
                // Try to withdraw exact balance
                try pool.withdraw(address(assetToken), aTokenBalance, address(this)) returns (uint256 withdrawnAmount) {
                    recovered = withdrawnAmount;
                } catch {
                    // Emergency exit failed
                }
            }
        }

        // Transfer any remaining tokens to vault
        uint256 remainingBalance = assetToken.balanceOf(address(this));
        if (remainingBalance > 0) {
            assetToken.safeTransfer(vault, remainingBalance);
            recovered = remainingBalance;
        }

        emit EmergencyExitExecuted(recovered);
    }

    function getBalance() external view returns (uint256) {
        return _getTotalBalance();
    }

    // ====================================================================
    // INTERNAL FUNCTIONS
    // ====================================================================

    function _getATokenAddress(address asset) internal view returns (address) {
        try pool.getReserveData(asset) returns (
            uint256,
            uint128,
            uint128,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address aTokenAddress,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return aTokenAddress;
        } catch {
            return address(0);
        }
    }

    function _getTotalBalance() internal view returns (uint256) {
        if (address(aToken) == address(0)) {
            return assetToken.balanceOf(address(this));
        }
        return aToken.balanceOf(address(this)) + assetToken.balanceOf(address(this));
    }

    function _updateLiquidityIndex() internal {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            lastRecordedLiquidityIndex = uint256(liquidityIndex);
            lastSupplyRate = uint256(currentLiquidityRate);
            emit SupplyRateUpdated(lastSupplyRate);
        } catch {
            // Silently fail
        }
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getCurrentSupplyRate() external view returns (uint256) {
        try pool.getReserveData(address(assetToken)) returns (
            uint256,
            uint128,
            uint128 currentLiquidityRate,
            uint128,
            uint128,
            uint128,
            uint40,
            uint16,
            address,
            address,
            address,
            address,
            uint128,
            uint128,
            uint128
        ) {
            return uint256(currentLiquidityRate);
        } catch {
            return lastSupplyRate;
        }
    }

    function getSupplyAPY() external view returns (uint256) {
        uint256 supplyRate = this.getCurrentSupplyRate();
        // Convert from ray (1e27) to basis points (1e4)
        return supplyRate / 1e23; // Convert from ray to basis points
    }

    function getHealthFactor() external view returns (uint256) {
        try pool.getUserAccountData(address(this)) returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256 healthFactor
        ) {
            return healthFactor;
        } catch {
            return type(uint256).max; // No debt, infinite health factor
        }
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        uint256 avgHarvestAmount,
        uint256 lastHarvestTimestamp,
        uint256 currentAPY
    ) {
        uint256 avgHarvest = harvestCount > 0 ? totalHarvested / harvestCount : 0;
        uint256 apy = this.getSupplyAPY();

        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            avgHarvest,
            lastHarvestTime,
            apy
        );
    }

    function getDetailedPosition() external view returns (
        uint256 aTokenBalance,
        uint256 supplyRate,
        uint256 positionValue,
        uint256 liquidityIndex
    ) {
        aTokenBalance = address(aToken) != address(0) ? aToken.balanceOf(address(this)) : 0;
        supplyRate = this.getCurrentSupplyRate();
        positionValue = aTokenBalance;
        liquidityIndex = lastRecordedLiquidityIndex;
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setMaxSlippage(uint256 newSlippage) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newSlippage <= 1000, "Slippage too high"); // Max 10%
        maxSlippage = newSlippage;
    }

    function setMaxSingleDeployment(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSingleDeployment = newMax;
    }

    function setMinHarvestAmount(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minHarvestAmount = newMin;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (paused) {
            strategyPaused = true;
            emit StrategyPaused();
        } else {
            strategyPaused = false;
            emit StrategyUnpaused();
        }
    }

    function grantAgentRole(address agent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(AGENT_ROLE, agent);
    }

    function emergencyWithdrawAToken() external onlyRole(EMERGENCY_ROLE) {
        if (address(aToken) != address(0)) {
            uint256 aTokenBal = aToken.balanceOf(address(this));
            if (aTokenBal > 0) {
                aToken.safeTransfer(vault, aTokenBal); // Now uses safeTransfer correctly with IERC20
            }
        }
    }

    function underlyingToken() external view returns (address) {
        return address(assetToken);
    }

    function protocol() external view returns (address) {
        return address(pool);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }
}