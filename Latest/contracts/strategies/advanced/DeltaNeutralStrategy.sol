// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Perpetual/Futures trading interface (conceptual - would need actual protocol)
interface IPerpetualProtocol {
    function openPosition(
        address baseToken,
        bool isLong,
        uint256 amount,
        uint256 leverage
    ) external returns (uint256 positionId);
    
    function closePosition(uint256 positionId) external returns (uint256 pnl);
    
    function getPositionValue(uint256 positionId) external view returns (uint256 value, int256 pnl);
    
    function getMarkPrice(address baseToken) external view returns (uint256 price);
    
    function getFundingRate(address baseToken) external view returns (int256 fundingRate);
}

// More.Markets interface for spot lending
interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

/// @title DeltaNeutralStrategy - Market-Neutral Position Strategy
/// @notice Maintains long spot position and short perpetual position to capture yield while hedging price risk
/// @dev Combines spot lending with perpetual shorts to create delta-neutral exposure
contract DeltaNeutralStrategy is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ====================================================================
    // CONSTANTS & ROLES
    // ====================================================================
    
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Protocol addresses
    address public constant MORE_MARKETS_POOL = 0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d;
    address public constant PERP_PROTOCOL = 0x1234567890123456789012345678901234567890; // Placeholder
    
    // Token addresses
    address public constant WFLOW = 0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e;
    address public constant USDC = 0xF1815bd50389c46847f0Bda824eC8da914045D14;

    // ====================================================================
    // STATE VARIABLES
    // ====================================================================
    
    IPool public immutable lendingPool;
    IPerpetualProtocol public immutable perpProtocol;
    IERC20 public immutable baseAsset; // USDC
    IERC20 public immutable targetAsset; // FLOW
    
    address public vault;
    bool public strategyPaused;
    
    // Position tracking
    uint256 public totalDeployed;
    uint256 public spotPosition; // Amount in lending protocol
    uint256 public perpPositionId; // Perpetual position ID
    uint256 public perpPositionSize; // Size of perp position
    
    // Strategy parameters
    uint256 public targetHedgeRatio = 9500; // 95% hedge ratio (basis points)
    uint256 public rebalanceThreshold = 500; // 5% deviation triggers rebalance
    uint256 public maxPositionSize = 1000000 * 1e6; // 1M USDC max
    uint256 public minPositionSize = 1000 * 1e6; // 1K USDC min
    
    // Risk management
    uint256 public maxDrawdown = 1000; // 10% max drawdown
    uint256 public stopLossThreshold = 800; // 8% stop loss
    bool public autoRebalance = true;
    uint256 public lastRebalanceTime;
    uint256 public rebalanceInterval = 1 hours;
    
    // Performance tracking
    uint256 public totalHarvested;
    uint256 public lastHarvestTime;
    uint256 public harvestCount;
    int256 public cumulativeFundingReceived;
    uint256 public totalLendingRewards;
    
    // Position health
    uint256 public lastHealthCheck;
    bool public positionHealthy = true;
    int256 public unrealizedPnL;

    // ====================================================================
    // EVENTS
    // ====================================================================
    
    event StrategyExecuted(uint256 spotAmount, uint256 perpSize, uint256 hedgeRatio);
    event PositionRebalanced(uint256 oldSpot, uint256 newSpot, uint256 oldPerp, uint256 newPerp);
    event StrategyHarvested(uint256 lendingRewards, int256 fundingReceived, uint256 totalHarvested);
    event EmergencyExitExecuted(uint256 recoveredAmount, int256 perpPnL);
    event DeltaNeutralityBroken(uint256 deltaExposure, uint256 threshold);
    event PositionHealthCheck(bool healthy, int256 pnl, uint256 timestamp);

    // ====================================================================
    // CONSTRUCTOR
    // ====================================================================
    
    constructor(
        address _vault,
        address _baseAsset,
        address _targetAsset
    ) {
        require(_vault != address(0), "Invalid vault");
        require(_baseAsset != address(0), "Invalid base asset");
        require(_targetAsset != address(0), "Invalid target asset");

        vault = _vault;
        baseAsset = IERC20(_baseAsset);
        targetAsset = IERC20(_targetAsset);
        
        lendingPool = IPool(MORE_MARKETS_POOL);
        perpProtocol = IPerpetualProtocol(PERP_PROTOCOL);

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

    modifier healthCheck() {
        _checkPositionHealth();
        _;
        _updateHealthCheck();
    }

    // ====================================================================
    // MAIN STRATEGY FUNCTIONS
    // ====================================================================

    function execute(uint256 amount, bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
    {
        require(amount >= minPositionSize, "Amount below minimum");
        require(amount <= maxPositionSize, "Amount exceeds maximum");

        // Transfer base asset from vault
        baseAsset.safeTransferFrom(msg.sender, address(this), amount);

        // Decode parameters if provided
        uint256 hedgeRatio = targetHedgeRatio;
        if (data.length > 0) {
            (hedgeRatio) = abi.decode(data, (uint256));
            require(hedgeRatio <= 10000, "Invalid hedge ratio");
        }

        // Execute delta-neutral strategy
        _executeDeltaNeutralPosition(amount, hedgeRatio);

        totalDeployed += amount;

        emit StrategyExecuted(spotPosition, perpPositionSize, hedgeRatio);
    }

    function harvest(bytes calldata data) 
        external 
        onlyVault 
        nonReentrant 
        whenNotPaused 
        healthCheck 
    {
        uint256 balanceBefore = baseAsset.balanceOf(address(this));

        // 1. Check if rebalancing is needed
        if (autoRebalance && _needsRebalancing()) {
            _rebalancePosition();
        }

        // 2. Harvest lending rewards
        uint256 lendingRewards = _harvestLendingRewards();

        // 3. Collect funding payments from perp position
        int256 fundingReceived = _collectFundingPayments();

        // 4. Update performance tracking
        totalLendingRewards += lendingRewards;
        cumulativeFundingReceived += fundingReceived;

        // 5. Transfer harvested amount to vault
        uint256 balanceAfter = baseAsset.balanceOf(address(this));
        uint256 actualHarvested = balanceAfter - balanceBefore;

        if (actualHarvested > 0) {
            baseAsset.safeTransfer(vault, actualHarvested);
            totalHarvested += actualHarvested;
            harvestCount++;
        }

        lastHarvestTime = block.timestamp;
        emit StrategyHarvested(lendingRewards, fundingReceived, actualHarvested);
    }

    function emergencyExit(bytes calldata data) 
        external 
        onlyRole(EMERGENCY_ROLE) 
        nonReentrant 
    {
        strategyPaused = true;

        uint256 recovered = 0;
        int256 perpPnL = 0;

        // 1. Close perpetual position
        if (perpPositionId != 0) {
            try perpProtocol.closePosition(perpPositionId) returns (uint256 pnl) {
                perpPnL = int256(pnl);
            } catch {
                // Position closing failed
            }
            perpPositionId = 0;
            perpPositionSize = 0;
        }

        // 2. Withdraw from lending protocol
        if (spotPosition > 0) {
            try lendingPool.withdraw(address(baseAsset), type(uint256).max, address(this)) returns (uint256 withdrawn) {
                recovered += withdrawn;
            } catch {
                // Withdrawal failed
            }
            spotPosition = 0;
        }

        // 3. Transfer remaining balance to vault
        uint256 remainingBalance = baseAsset.balanceOf(address(this));
        if (remainingBalance > 0) {
            baseAsset.safeTransfer(vault, remainingBalance);
            recovered += remainingBalance;
        }

        emit EmergencyExitExecuted(recovered, perpPnL);
    }

    // ====================================================================
    // DELTA NEUTRAL LOGIC
    // ====================================================================

    function _executeDeltaNeutralPosition(uint256 amount, uint256 hedgeRatio) internal {
        // Split amount between spot and perp based on hedge ratio
        uint256 spotAmount = amount;
        uint256 perpNotional = (amount * hedgeRatio) / 10000;

        // 1. Supply to lending protocol for yield
        baseAsset.approve(address(lendingPool), spotAmount);
        lendingPool.supply(address(baseAsset), spotAmount, address(this), 0);
        spotPosition += spotAmount;

        // 2. Open short perpetual position to hedge price exposure
        if (perpNotional > 0) {
            // Convert USDC notional to target asset amount for perp
            uint256 targetAssetPrice = perpProtocol.getMarkPrice(address(targetAsset));
            uint256 perpSize = (perpNotional * 1e18) / targetAssetPrice;

            // Open short position
            uint256 positionId = perpProtocol.openPosition(
                address(targetAsset),
                false, // Short position
                perpSize,
                1 // 1x leverage for delta neutrality
            );

            // Update position tracking
            if (perpPositionId == 0) {
                perpPositionId = positionId;
                perpPositionSize = perpSize;
            } else {
                // Add to existing position
                perpPositionSize += perpSize;
            }
        }
    }

    function _needsRebalancing() internal view returns (bool) {
        if (block.timestamp < lastRebalanceTime + rebalanceInterval) {
            return false;
        }

        // Check if delta exposure has drifted beyond threshold
        uint256 deltaExposure = _calculateDeltaExposure();
        uint256 targetExposure = (spotPosition * (10000 - targetHedgeRatio)) / 10000;
        
        if (targetExposure == 0) return false;
        
        uint256 deviationBps = deltaExposure > targetExposure ?
            ((deltaExposure - targetExposure) * 10000) / targetExposure :
            ((targetExposure - deltaExposure) * 10000) / targetExposure;

        return deviationBps > rebalanceThreshold;
    }

    function _rebalancePosition() internal {
        uint256 oldSpotPosition = spotPosition;
        uint256 oldPerpSize = perpPositionSize;

        // Calculate current delta exposure
        uint256 currentDelta = _calculateDeltaExposure();
        uint256 targetDelta = (spotPosition * (10000 - targetHedgeRatio)) / 10000;

        if (currentDelta > targetDelta) {
            // Too much delta exposure, increase hedge
            uint256 additionalHedge = currentDelta - targetDelta;
            _adjustPerpPosition(additionalHedge, true); // Increase short
        } else if (currentDelta < targetDelta) {
            // Too little delta exposure, decrease hedge
            uint256 hedgeReduction = targetDelta - currentDelta;
            _adjustPerpPosition(hedgeReduction, false); // Decrease short
        }

        lastRebalanceTime = block.timestamp;
        emit PositionRebalanced(oldSpotPosition, spotPosition, oldPerpSize, perpPositionSize);
    }

    function _adjustPerpPosition(uint256 amount, bool increaseShort) internal {
        uint256 targetAssetPrice = perpProtocol.getMarkPrice(address(targetAsset));
        uint256 sizeChange = (amount * 1e18) / targetAssetPrice;

        if (increaseShort) {
            // Open additional short position
            uint256 newPositionId = perpProtocol.openPosition(
                address(targetAsset),
                false,
                sizeChange,
                1
            );
            
            if (perpPositionId == 0) {
                perpPositionId = newPositionId;
            }
            perpPositionSize += sizeChange;
        } else {
            // Reduce short position
            if (sizeChange >= perpPositionSize) {
                // Close entire position
                perpProtocol.closePosition(perpPositionId);
                perpPositionId = 0;
                perpPositionSize = 0;
            } else {
                // Partially close position (conceptual - would need partial close function)
                perpPositionSize -= sizeChange;
            }
        }
    }

    function _calculateDeltaExposure() internal view returns (uint256) {
        if (perpPositionSize == 0) {
            return spotPosition; // Fully exposed to spot price
        }

        uint256 targetAssetPrice = perpProtocol.getMarkPrice(address(targetAsset));
        uint256 perpNotional = (perpPositionSize * targetAssetPrice) / 1e18;
        
        // Delta exposure = spot position - hedge notional
        return spotPosition > perpNotional ? spotPosition - perpNotional : 0;
    }

    // ====================================================================
    // YIELD COLLECTION
    // ====================================================================

    function _harvestLendingRewards() internal returns (uint256 rewards) {
        // Get current position value from lending protocol
        (uint256 totalCollateralBase,,,,,) = lendingPool.getUserAccountData(address(this));
        
        if (totalCollateralBase > spotPosition) {
            rewards = totalCollateralBase - spotPosition;
            
            // Withdraw rewards
            if (rewards > 0) {
                lendingPool.withdraw(address(baseAsset), rewards, address(this));
            }
        }
        
        return rewards;
    }

    function _collectFundingPayments() internal returns (int256 fundingReceived) {
        // Get funding rate for the target asset
        int256 fundingRate = perpProtocol.getFundingRate(address(targetAsset));
        
        // Calculate funding payment based on position size
        // Funding payment = position_size * funding_rate * time_fraction
        uint256 timeElapsed = block.timestamp - lastHarvestTime;
        if (timeElapsed > 0 && perpPositionSize > 0) {
            // Simplified funding calculation (8 hour periods typically)
            fundingReceived = int256(perpPositionSize) * fundingRate * int256(timeElapsed) / int256(8 hours);
        }
        
        return fundingReceived;
    }

    // ====================================================================
    // HEALTH MONITORING
    // ====================================================================

    function _checkPositionHealth() internal {
        // Check for excessive PnL - FIXED VERSION
        uint256 positionValue;
        int256 pnl;
        
        if (perpPositionId != 0) {
            (positionValue, pnl) = perpProtocol.getPositionValue(perpPositionId);
        } else {
            positionValue = 0;
            pnl = int256(0);
        }
        
        unrealizedPnL = pnl;
        
        // Check if position is healthy
        bool wasHealthy = positionHealthy;
        positionHealthy = true;
        
        // Check stop loss
        if (pnl < 0 && uint256(-pnl) > (totalDeployed * stopLossThreshold) / 10000) {
            positionHealthy = false;
        }
        
        // Check max drawdown
        uint256 currentValue = getBalance();
        if (totalDeployed > 0 && currentValue < (totalDeployed * (10000 - maxDrawdown)) / 10000) {
            positionHealthy = false;
        }
        
        // Check delta neutrality
        uint256 deltaExposure = _calculateDeltaExposure();
        uint256 maxAllowedDelta = (spotPosition * rebalanceThreshold) / 10000;
        if (deltaExposure > maxAllowedDelta) {
            emit DeltaNeutralityBroken(deltaExposure, maxAllowedDelta);
        }
        
        if (wasHealthy != positionHealthy) {
            emit PositionHealthCheck(positionHealthy, pnl, block.timestamp);
        }
    }

    function _updateHealthCheck() internal {
        lastHealthCheck = block.timestamp;
    }

    // ====================================================================
    // ENHANCED STRATEGY INTERFACE
    // ====================================================================

    function getHealthFactor() external view returns (uint256) {
        if (!positionHealthy) return 0;
        
        // Calculate health based on PnL and exposure
        uint256 currentValue = getBalance();
        if (totalDeployed == 0) return type(uint256).max;
        
        return (currentValue * 1e18) / totalDeployed;
    }

    function getLeverageRatio() external pure returns (uint256) {
        return 1e18; // Delta neutral strategy uses 1x effective leverage
    }

    function getPositionValue() external view returns (uint256 collateral, uint256 debt) {
        collateral = spotPosition;
        debt = 0; // No debt in delta neutral strategy
    }

    function checkLiquidationRisk() external view returns (bool atRisk, uint256 buffer) {
        atRisk = !positionHealthy;
        
        // Calculate buffer based on distance to stop loss
        uint256 currentValue = getBalance();
        uint256 stopLossValue = (totalDeployed * (10000 - stopLossThreshold)) / 10000;
        
        buffer = currentValue > stopLossValue ? currentValue - stopLossValue : 0;
    }

    function getMaxWithdrawable() external view returns (uint256) {
        return getBalance();
    }

    function adjustLeverage(uint256 targetRatio, uint256 maxSlippage) external onlyRole(AGENT_ROLE) {
        require(targetRatio <= 10000, "Invalid ratio");
        targetHedgeRatio = targetRatio;
        _rebalancePosition();
    }

    function emergencyDelever() external onlyRole(AGENT_ROLE) {
        if (!positionHealthy) {
            // Close perp position to reduce risk
            if (perpPositionId != 0) {
                perpProtocol.closePosition(perpPositionId);
                perpPositionId = 0;
                perpPositionSize = 0;
            }
        }
    }

    function rebalance(bytes calldata rebalanceData) external onlyRole(AGENT_ROLE) {
        _rebalancePosition();
    }

    function setRiskParameters(
        uint256 maxLeverage,
        uint256 targetHealthFactor,
        uint256 liquidationBuffer
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Delta neutral strategy doesn't use traditional leverage
        maxDrawdown = liquidationBuffer;
        stopLossThreshold = liquidationBuffer * 80 / 100; // 80% of max drawdown
    }

    // ====================================================================
    // VIEW FUNCTIONS
    // ====================================================================

    function getBalance() public view returns (uint256) {
        uint256 spotValue = spotPosition;
        
        // Add unrealized PnL from perp position
        if (perpPositionId != 0) {
            (uint256 positionValue, int256 pnl) = perpProtocol.getPositionValue(perpPositionId);
            if (pnl > 0) {
                spotValue += uint256(pnl);
            } else if (uint256(-pnl) < spotValue) {
                spotValue -= uint256(-pnl);
            } else {
                spotValue = 0;
            }
        }
        
        return spotValue + baseAsset.balanceOf(address(this));
    }

    function getPositionDetails() external view returns (
        uint256 spotAmount,
        uint256 perpSize,
        uint256 hedgeRatio,
        uint256 deltaExposure,
        int256 unrealizedPnl,
        bool isHealthy
    ) {
        spotAmount = spotPosition;
        perpSize = perpPositionSize;
        hedgeRatio = targetHedgeRatio;
        deltaExposure = _calculateDeltaExposure();
        unrealizedPnl = unrealizedPnL;
        isHealthy = positionHealthy;
    }

    function getPerformanceMetrics() external view returns (
        uint256 totalDeployedAmount,
        uint256 totalHarvestedAmount,
        uint256 harvestsCount,
        int256 cumulativeFunding,
        uint256 lendingRewards,
        uint256 currentBalance
    ) {
        return (
            totalDeployed,
            totalHarvested,
            harvestCount,
            cumulativeFundingReceived,
            totalLendingRewards,
            getBalance()
        );
    }

    // ====================================================================
    // ADMIN FUNCTIONS
    // ====================================================================

    function setTargetHedgeRatio(uint256 _targetHedgeRatio) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_targetHedgeRatio <= 10000, "Invalid hedge ratio");
        targetHedgeRatio = _targetHedgeRatio;
    }

    function setRebalanceParameters(
        uint256 _rebalanceThreshold,
        uint256 _rebalanceInterval,
        bool _autoRebalance
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rebalanceThreshold = _rebalanceThreshold;
        rebalanceInterval = _rebalanceInterval;
        autoRebalance = _autoRebalance;
    }

    function setRiskLimits(
        uint256 _maxDrawdown,
        uint256 _stopLossThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_maxDrawdown <= 5000, "Max drawdown too high"); // Max 50%
        require(_stopLossThreshold <= _maxDrawdown, "Stop loss higher than max drawdown");
        
        maxDrawdown = _maxDrawdown;
        stopLossThreshold = _stopLossThreshold;
    }

    function setPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        strategyPaused = paused;
    }

    // IStrategy interface compatibility
    function underlyingToken() external view returns (address) {
        return address(baseAsset);
    }

    function protocol() external view returns (address) {
        return address(lendingPool);
    }

    function paused() external view returns (bool) {
        return strategyPaused;
    }
}