// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./BaseStrategy.sol";

// Flowty Marketplace Interfaces (Real Flow NFT marketplace)
interface IFlowtyMarketplace {
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 duration
    ) external;

    function buyNFT(
        address nftContract,
        uint256 tokenId
    ) external payable;

    function cancelListing(
        address nftContract,
        uint256 tokenId
    ) external;

    function getListing(
        address nftContract,
        uint256 tokenId
    ) external view returns (
        address seller,
        uint256 price,
        uint256 expiry,
        bool active
    );

    function getFloorPrice(address nftContract) external view returns (uint256);
    function getCollectionVolume(address nftContract) external view returns (uint256);
}

// NFT Staking Interface
interface INFTStaking {
    function stakeNFT(address nftContract, uint256 tokenId) external;
    function unstakeNFT(address nftContract, uint256 tokenId) external;
    function claimRewards(address nftContract, uint256 tokenId) external returns (uint256);
    function getStakedRewards(address nftContract, uint256 tokenId) external view returns (uint256);
    function getStakingAPY(address nftContract) external view returns (uint256);
}

// NFT Lending Interface
interface INFTLending {
    function collateralizeNFT(
        address nftContract,
        uint256 tokenId,
        uint256 loanAmount
    ) external;

    function repayLoan(uint256 loanId) external;
    function liquidateNFT(uint256 loanId) external;
    
    function getLoanDetails(uint256 loanId) external view returns (
        address borrower,
        address nftContract,
        uint256 tokenId,
        uint256 loanAmount,
        uint256 interestRate,
        uint256 dueDate,
        bool active
    );
}

/// @title FlowNFTYieldStrategy - NFT-Powered Yield Generation
/// @notice Revolutionary strategy leveraging Flow's NFT ecosystem for yield
contract FlowNFTYieldStrategy is BaseStrategy, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Flowty and NFT protocol addresses (you'll need real addresses)
    address public constant FLOWTY_MARKETPLACE = address(0); // TODO: Real Flowty address
    address public constant NBA_TOPSHOT_CONTRACT = address(0); // NBA Top Shot NFTs
    address public constant NFL_ALLDAY_CONTRACT = address(0); // NFL All Day NFTs
    address public constant NFT_STAKING_CONTRACT = address(0); // NFT staking protocol
    address public constant NFT_LENDING_CONTRACT = address(0); // NFT lending protocol

    IFlowtyMarketplace public immutable flowtyMarketplace;
    INFTStaking public immutable nftStaking;
    INFTLending public immutable nftLending;

    // NFT Strategy Configuration
    struct NFTPosition {
        address nftContract;
        uint256 tokenId;
        uint256 purchasePrice;
        uint256 purchaseTime;
        StrategyType strategyType;
        bool active;
        uint256 currentValue;
        uint256 accruedRewards;
    }

    enum StrategyType {
        FLIP_TRADING,     // Buy low, sell high
        STAKE_REWARDS,    // Stake for token rewards
        COLLATERAL_LOAN,  // Use as collateral for loans
        RENTAL_YIELD,     // Rent out for yield
        FRACTIONAL_OWNERSHIP // Fractionalize expensive NFTs
    }

    // State variables
    mapping(uint256 => NFTPosition) public nftPositions;
    mapping(address => uint256[]) public nftsByContract;
    uint256 public positionCounter;
    uint256 public totalNFTValue;
    uint256 public totalRewardsEarned;

    // Strategy parameters
    uint256 public maxNFTPurchasePrice = 1000 * 10**6; // 1000 USDC max per NFT
    uint256 public minProfitMargin = 1000; // 10% minimum profit
    uint256 public maxHoldingPeriod = 90 days;
    uint256 public floorPriceBuffer = 1500; // 15% above floor price

    // Performance tracking
    mapping(address => uint256) public collectionPerformance;
    mapping(StrategyType => uint256) public strategyPerformance;

    event NFTPurchased(address indexed nftContract, uint256 indexed tokenId, uint256 price, StrategyType strategy);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, uint256 sellPrice, uint256 profit);
    event NFTStaked(address indexed nftContract, uint256 indexed tokenId, uint256 expectedAPY);
    event NFTCollateralized(address indexed nftContract, uint256 indexed tokenId, uint256 loanAmount);
    event RewardsClaimed(address indexed nftContract, uint256 indexed tokenId, uint256 amount);

    constructor(
        address _asset,
        address _vault,
        string memory _name
    ) BaseStrategy(_asset, FLOWTY_MARKETPLACE, _vault, _name) {
        flowtyMarketplace = IFlowtyMarketplace(FLOWTY_MARKETPLACE);
        nftStaking = INFTStaking(NFT_STAKING_CONTRACT);
        nftLending = INFTLending(NFT_LENDING_CONTRACT);
    }

    function _executeStrategy(uint256 amount, bytes calldata data) internal override {
        // Decode NFT strategy parameters
        (StrategyType strategyType, address targetCollection, uint256 maxPrice) = data.length > 0 
            ? abi.decode(data, (StrategyType, address, uint256))
            : (StrategyType.FLIP_TRADING, NBA_TOPSHOT_CONTRACT, maxNFTPurchasePrice);

        if (strategyType == StrategyType.FLIP_TRADING) {
            _executeFlipTrading(amount, targetCollection, maxPrice);
        } else if (strategyType == StrategyType.STAKE_REWARDS) {
            _executeStakingStrategy(amount, targetCollection, maxPrice);
        } else if (strategyType == StrategyType.COLLATERAL_LOAN) {
            _executeCollateralStrategy(amount, targetCollection, maxPrice);
        }
    }

    function _executeFlipTrading(uint256 amount, address collection, uint256 maxPrice) internal {
        // Analyze floor price and find undervalued NFTs
        uint256 floorPrice = flowtyMarketplace.getFloorPrice(collection);
        uint256 targetPrice = (floorPrice * (10000 + floorPriceBuffer)) / 10000;

        if (targetPrice <= maxPrice && targetPrice <= amount) {
            // Find and purchase undervalued NFT
            _purchaseUndervaluedNFT(collection, targetPrice);
        }
    }

    function _executeStakingStrategy(uint256 amount, address collection, uint256 maxPrice) internal {
        // Purchase NFT specifically for staking rewards
        uint256 stakingAPY = nftStaking.getStakingAPY(collection);
        
        if (stakingAPY >= 500) { // 5% minimum APY
            _purchaseNFTForStaking(collection, maxPrice, amount);
        }
    }

    function _executeCollateralStrategy(uint256 amount, address collection, uint256 maxPrice) internal {
        // Purchase blue-chip NFTs to use as collateral for borrowing
        if (_isBlueChipCollection(collection)) {
            _purchaseNFTForCollateral(collection, maxPrice, amount);
        }
    }

    function _purchaseUndervaluedNFT(address collection, uint256 maxPrice) internal {
        // Mock implementation - in reality would scan marketplace listings
        // For demonstration, assume we found an NFT at tokenId 1
        uint256 tokenId = 1;
        uint256 listingPrice = _getMockListingPrice(collection, tokenId);

        if (listingPrice <= maxPrice && listingPrice > 0) {
            // Purchase the NFT
            assetToken.approve(address(flowtyMarketplace), listingPrice);
            
            try flowtyMarketplace.buyNFT{value: listingPrice}(collection, tokenId) {
                // Record the position
                positionCounter++;
                nftPositions[positionCounter] = NFTPosition({
                    nftContract: collection,
                    tokenId: tokenId,
                    purchasePrice: listingPrice,
                    purchaseTime: block.timestamp,
                    strategyType: StrategyType.FLIP_TRADING,
                    active: true,
                    currentValue: listingPrice,
                    accruedRewards: 0
                });

                nftsByContract[collection].push(positionCounter);
                totalNFTValue += listingPrice;

                emit NFTPurchased(collection, tokenId, listingPrice, StrategyType.FLIP_TRADING);
            } catch {
                // Purchase failed
            }
        }
    }

    function _purchaseNFTForStaking(address collection, uint256 maxPrice, uint256 amount) internal {
        uint256 tokenId = 2; // Mock tokenId
        uint256 price = _getMockListingPrice(collection, tokenId);

        if (price <= maxPrice && price <= amount) {
            assetToken.approve(address(flowtyMarketplace), price);
            
            try flowtyMarketplace.buyNFT{value: price}(collection, tokenId) {
                // Immediately stake the NFT
                IERC721(collection).approve(address(nftStaking), tokenId);
                nftStaking.stakeNFT(collection, tokenId);

                positionCounter++;
                nftPositions[positionCounter] = NFTPosition({
                    nftContract: collection,
                    tokenId: tokenId,
                    purchasePrice: price,
                    purchaseTime: block.timestamp,
                    strategyType: StrategyType.STAKE_REWARDS,
                    active: true,
                    currentValue: price,
                    accruedRewards: 0
                });

                nftsByContract[collection].push(positionCounter);
                totalNFTValue += price;

                emit NFTPurchased(collection, tokenId, price, StrategyType.STAKE_REWARDS);
                emit NFTStaked(collection, tokenId, nftStaking.getStakingAPY(collection));
            } catch {
                // Purchase or staking failed
            }
        }
    }

    function _purchaseNFTForCollateral(address collection, uint256 maxPrice, uint256 amount) internal {
        uint256 tokenId = 3; // Mock tokenId
        uint256 price = _getMockListingPrice(collection, tokenId);

        if (price <= maxPrice && price <= amount) {
            assetToken.approve(address(flowtyMarketplace), price);
            
            try flowtyMarketplace.buyNFT{value: price}(collection, tokenId) {
                // Use NFT as collateral for loan
                uint256 loanAmount = (price * 7000) / 10000; // 70% LTV
                IERC721(collection).approve(address(nftLending), tokenId);
                nftLending.collateralizeNFT(collection, tokenId, loanAmount);

                positionCounter++;
                nftPositions[positionCounter] = NFTPosition({
                    nftContract: collection,
                    tokenId: tokenId,
                    purchasePrice: price,
                    purchaseTime: block.timestamp,
                    strategyType: StrategyType.COLLATERAL_LOAN,
                    active: true,
                    currentValue: price,
                    accruedRewards: 0
                });

                nftsByContract[collection].push(positionCounter);
                totalNFTValue += price;

                emit NFTPurchased(collection, tokenId, price, StrategyType.COLLATERAL_LOAN);
                emit NFTCollateralized(collection, tokenId, loanAmount);
            } catch {
                // Purchase or collateralization failed
            }
        }
    }

    function _harvestRewards(bytes calldata) internal override {
        // Harvest rewards from all active NFT positions
        for (uint256 i = 1; i <= positionCounter; i++) {
            NFTPosition storage position = nftPositions[i];
            
            if (position.active) {
                if (position.strategyType == StrategyType.STAKE_REWARDS) {
                    _harvestStakingRewards(i);
                } else if (position.strategyType == StrategyType.FLIP_TRADING) {
                    _checkFlipOpportunity(i);
                }
                
                _updatePositionValue(i);
            }
        }
    }

    function _harvestStakingRewards(uint256 positionId) internal {
        NFTPosition storage position = nftPositions[positionId];
        
        try nftStaking.claimRewards(position.nftContract, position.tokenId) returns (uint256 rewards) {
            if (rewards > 0) {
                position.accruedRewards += rewards;
                totalRewardsEarned += rewards;
                
                emit RewardsClaimed(position.nftContract, position.tokenId, rewards);
            }
        } catch {
            // Claim failed
        }
    }

    function _checkFlipOpportunity(uint256 positionId) internal {
        NFTPosition storage position = nftPositions[positionId];
        
        // Check if enough time has passed or if profit margin is met
        uint256 currentPrice = _getCurrentNFTPrice(position.nftContract, position.tokenId);
        uint256 profitMargin = currentPrice > position.purchasePrice 
            ? ((currentPrice - position.purchasePrice) * 10000) / position.purchasePrice
            : 0;

        bool shouldSell = profitMargin >= minProfitMargin || 
                         (block.timestamp - position.purchaseTime) >= maxHoldingPeriod;

        if (shouldSell && currentPrice > position.purchasePrice) {
            _sellNFT(positionId, currentPrice);
        }
    }

    function _sellNFT(uint256 positionId, uint256 price) internal {
        NFTPosition storage position = nftPositions[positionId];
        
        // List NFT for sale on Flowty
        IERC721(position.nftContract).approve(address(flowtyMarketplace), position.tokenId);
        
        try flowtyMarketplace.listNFT(
            position.nftContract,
            position.tokenId,
            price,
            7 days
        ) {
            // In a real implementation, would wait for sale completion
            // For demo, assume immediate sale
            uint256 profit = price > position.purchasePrice ? price - position.purchasePrice : 0;
            
            position.active = false;
            totalNFTValue -= position.purchasePrice;
            strategyPerformance[position.strategyType] += profit;
            
            emit NFTSold(position.nftContract, position.tokenId, price, profit);
        } catch {
            // Listing failed
        }
    }

    function _emergencyWithdraw(bytes calldata) internal override returns (uint256 recovered) {
        // Emergency liquidation of all NFT positions
        for (uint256 i = 1; i <= positionCounter; i++) {
            NFTPosition storage position = nftPositions[i];
            
            if (position.active) {
                if (position.strategyType == StrategyType.STAKE_REWARDS) {
                    // Unstake NFT
                    try nftStaking.unstakeNFT(position.nftContract, position.tokenId) {
                        // Unstaked successfully
                    } catch {
                        // Unstaking failed
                    }
                }
                
                // Emergency sell at floor price
                uint256 floorPrice = flowtyMarketplace.getFloorPrice(position.nftContract);
                _sellNFT(i, floorPrice);
                
                recovered += floorPrice;
            }
        }
        
        return recovered;
    }

    function getBalance() external view override returns (uint256) {
        uint256 totalValue = assetToken.balanceOf(address(this));
        
        // Add current value of all NFT positions
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (nftPositions[i].active) {
                totalValue += nftPositions[i].currentValue;
                totalValue += nftPositions[i].accruedRewards;
            }
        }
        
        return totalValue;
    }

    function _updatePositionValue(uint256 positionId) internal {
        NFTPosition storage position = nftPositions[positionId];
        position.currentValue = _getCurrentNFTPrice(position.nftContract, position.tokenId);
        
        if (position.strategyType == StrategyType.STAKE_REWARDS) {
            position.accruedRewards += nftStaking.getStakedRewards(position.nftContract, position.tokenId);
        }
    }

    function _getCurrentNFTPrice(address nftContract, uint256 tokenId) internal view returns (uint256) {
        // Mock implementation - would integrate with real price feeds
        uint256 floorPrice = flowtyMarketplace.getFloorPrice(nftContract);
        return floorPrice + (floorPrice * 10) / 100; // Add 10% premium
    }

    function _getMockListingPrice(address collection, uint256 tokenId) internal view returns (uint256) {
        // Mock function - in reality would scan actual listings
        uint256 floorPrice = flowtyMarketplace.getFloorPrice(collection);
        return floorPrice - (floorPrice * 5) / 100; // 5% below floor
    }

    function _isBlueChipCollection(address collection) internal pure returns (bool) {
        return collection == NBA_TOPSHOT_CONTRACT || collection == NFL_ALLDAY_CONTRACT;
    }

    // Admin functions
    function setMaxNFTPurchasePrice(uint256 _maxPrice) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxNFTPurchasePrice = _maxPrice;
    }

    function setMinProfitMargin(uint256 _minMargin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_minMargin <= 5000, "Margin too high"); // Max 50%
        minProfitMargin = _minMargin;
    }

    function setMaxHoldingPeriod(uint256 _maxPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxHoldingPeriod = _maxPeriod;
    }

    function manualSellNFT(uint256 positionId, uint256 price) external onlyRole(HARVESTER_ROLE) {
        require(positionId <= positionCounter, "Invalid position");
        require(nftPositions[positionId].active, "Position not active");
        _sellNFT(positionId, price);
    }

    // View functions
    function getAllPositions() external view returns (NFTPosition[] memory) {
        NFTPosition[] memory positions = new NFTPosition[](positionCounter);
        for (uint256 i = 1; i <= positionCounter; i++) {
            positions[i - 1] = nftPositions[i];
        }
        return positions;
    }

    function getActivePositions() external view returns (NFTPosition[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (nftPositions[i].active) activeCount++;
        }
        
        NFTPosition[] memory activePositions = new NFTPosition[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= positionCounter; i++) {
            if (nftPositions[i].active) {
                activePositions[index] = nftPositions[i];
                index++;
            }
        }
        
        return activePositions;
    }

    function getStrategyPerformance() external view returns (
        uint256 flipTrading,
        uint256 stakeRewards,
        uint256 collateralLoan,
        uint256 totalNFTVal,
        uint256 totalRewards
    ) {
        return (
            strategyPerformance[StrategyType.FLIP_TRADING],
            strategyPerformance[StrategyType.STAKE_REWARDS],
            strategyPerformance[StrategyType.COLLATERAL_LOAN],
            totalNFTValue,
            totalRewardsEarned
        );
    }

    // Required for receiving NFTs
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // Handle native Flow for NFT purchases
    receive() external payable {}
}