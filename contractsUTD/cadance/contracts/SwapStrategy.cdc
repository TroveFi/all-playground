import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import stFlowToken from 0xd6f80565193ad727
import SwapRouter from 0xa6850776a94e6551
import SwapInterfaces from 0xb78ef7afa52ff906
import LiquidStaking from 0xd6f80565193ad727

/// DEX swap strategy for rebalancing and optimal routing
/// Supports: SwapRouter, Increment v1/stable pairs, LiquidStaking direct
access(all) contract SwapStrategy {
    
    // ====================================================================
    // CONSTANTS
    // ====================================================================
    access(all) let INCREMENT_V1_PAIR: Address
    access(all) let INCREMENT_STABLE_PAIR: Address
    
    // ====================================================================
    // EVENTS
    // ====================================================================
    access(all) event Swapped(fromToken: String, toToken: String, amountIn: UFix64, amountOut: UFix64, route: String)
    access(all) event OptimalRouteFound(route: String, expectedOutput: UFix64)
    
    // ====================================================================
    // STATE
    // ====================================================================
    access(self) var totalSwaps: UInt64
    access(self) var totalVolumeByPair: {String: UFix64}
    
    // ====================================================================
    // ENUMS
    // ====================================================================
    access(all) enum SwapRoute: UInt8 {
        access(all) case liquidStaking    // Direct FLOW -> stFLOW via LiquidStaking
        access(all) case incrementV1      // Increment v1 DEX
        access(all) case incrementStable  // Increment stable swap
        access(all) case swapRouter       // General SwapRouter
    }
    
    // ====================================================================
    // STRUCTS
    // ====================================================================
    access(all) struct RouteQuote {
        access(all) let route: SwapRoute
        access(all) let expectedOutput: UFix64
        access(all) let routeName: String
        
        init(route: SwapRoute, expectedOutput: UFix64, routeName: String) {
            self.route = route
            self.expectedOutput = expectedOutput
            self.routeName = routeName
        }
    }
    
    // ====================================================================
    // STRATEGY RESOURCE
    // ====================================================================
    access(all) resource Strategy {
        access(self) let flowVault: @FlowToken.Vault
        access(self) let stFlowVault: @stFlowToken.Vault
        
        init() {
            self.flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()) as! @FlowToken.Vault
            self.stFlowVault <- stFlowToken.createEmptyVault(vaultType: Type<@stFlowToken.Vault>()) as! @stFlowToken.Vault
        }
        
        /// Execute swap with optimal route selection (FLOW -> stFLOW)
        access(all) fun swapFlowToStFlow(from: @FlowToken.Vault): @stFlowToken.Vault {
            pre {
                from.balance > 0.0: "Cannot swap zero"
            }
            
            let amount = from.balance
            
            // Find optimal route
            let bestRoute = self.findOptimalRouteFlowToStFlow(amount: amount)
            
            emit OptimalRouteFound(route: bestRoute.routeName, expectedOutput: bestRoute.expectedOutput)
            
            // Execute via best route
            switch bestRoute.route {
                case SwapRoute.liquidStaking:
                    let result <- LiquidStaking.stake(flowVault: <-from)
                    emit Swapped(fromToken: "FLOW", toToken: "stFLOW", amountIn: amount, amountOut: result.balance, route: "LiquidStaking")
                    return <- result
                
                case SwapRoute.incrementV1:
                    let result <- self.swapViaIncrementV1(from: <-from)
                    emit Swapped(fromToken: "FLOW", toToken: "stFLOW", amountIn: amount, amountOut: result.balance, route: "IncrementV1")
                    return <- result
                
                case SwapRoute.incrementStable:
                    let result <- self.swapViaIncrementStable(from: <-from)
                    emit Swapped(fromToken: "FLOW", toToken: "stFLOW", amountIn: amount, amountOut: result.balance, route: "IncrementStable")
                    return <- result
                
                case SwapRoute.swapRouter:
                    let result <- self.swapViaRouter(from: <-from)
                    emit Swapped(fromToken: "FLOW", toToken: "stFLOW", amountIn: amount, amountOut: result.balance, route: "SwapRouter")
                    return <- result
            }
            
            // Fallback (should never reach)
            return <- LiquidStaking.stake(flowVault: <-from)
        }
        
        /// Execute swap with optimal route selection (stFLOW -> FLOW)
        access(all) fun swapStFlowToFlow(from: @stFlowToken.Vault): @FlowToken.Vault {
            pre {
                from.balance > 0.0: "Cannot swap zero"
            }
            
            let amount = from.balance
            
            // For stFLOW -> FLOW, DEX is usually better than unstaking
            let bestRoute = self.findOptimalRouteStFlowToFlow(amount: amount)
            
            emit OptimalRouteFound(route: bestRoute.routeName, expectedOutput: bestRoute.expectedOutput)
            
            // Execute via best route
            switch bestRoute.route {
                case SwapRoute.incrementV1:
                    let result <- self.swapStFlowViaIncrementV1(from: <-from)
                    emit Swapped(fromToken: "stFLOW", toToken: "FLOW", amountIn: amount, amountOut: result.balance, route: "IncrementV1")
                    return <- result
                
                case SwapRoute.incrementStable:
                    let result <- self.swapStFlowViaIncrementStable(from: <-from)
                    emit Swapped(fromToken: "stFLOW", toToken: "FLOW", amountIn: amount, amountOut: result.balance, route: "IncrementStable")
                    return <- result
                
                case SwapRoute.swapRouter:
                    let result <- self.swapStFlowViaRouter(from: <-from)
                    emit Swapped(fromToken: "stFLOW", toToken: "FLOW", amountIn: amount, amountOut: result.balance, route: "SwapRouter")
                    return <- result
                
                default:
                    // Fallback to stable pair
                    let result <- self.swapStFlowViaIncrementStable(from: <-from)
                    emit Swapped(fromToken: "stFLOW", toToken: "FLOW", amountIn: amount, amountOut: result.balance, route: "IncrementStable")
                    return <- result
            }
        }
        
        /// Find optimal route for FLOW -> stFLOW
        access(all) fun findOptimalRouteFlowToStFlow(amount: UFix64): RouteQuote {
            var bestQuote = RouteQuote(
                route: SwapRoute.liquidStaking,
                expectedOutput: 0.0,
                routeName: "None"
            )
            
            // Option 1: LiquidStaking direct
            let stakingEstimate = LiquidStaking.calcStFlowFromFlow(flowAmount: amount)
            bestQuote = RouteQuote(
                route: SwapRoute.liquidStaking,
                expectedOutput: stakingEstimate,
                routeName: "LiquidStaking"
            )
            
            // Option 2: Increment v1 pair
            let pairV1 = getAccount(SwapStrategy.INCREMENT_V1_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            
            if pairV1 != nil {
                let v1Estimate = pairV1!.getAmountOut(
                    amountIn: amount,
                    tokenInKey: "A.1654653399040a61.FlowToken"
                )
                
                if v1Estimate > bestQuote.expectedOutput {
                    bestQuote = RouteQuote(
                        route: SwapRoute.incrementV1,
                        expectedOutput: v1Estimate,
                        routeName: "IncrementV1"
                    )
                }
            }
            
            // Option 3: Increment stable pair
            let pairStable = getAccount(SwapStrategy.INCREMENT_STABLE_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            
            if pairStable != nil {
                let stableEstimate = pairStable!.getAmountOut(
                    amountIn: amount,
                    tokenInKey: "A.1654653399040a61.FlowToken"
                )
                
                if stableEstimate > bestQuote.expectedOutput {
                    bestQuote = RouteQuote(
                        route: SwapRoute.incrementStable,
                        expectedOutput: stableEstimate,
                        routeName: "IncrementStable"
                    )
                }
            }
            
            return bestQuote
        }
        
        /// Find optimal route for stFLOW -> FLOW
        access(all) fun findOptimalRouteStFlowToFlow(amount: UFix64): RouteQuote {
            var bestQuote = RouteQuote(
                route: SwapRoute.incrementStable,
                expectedOutput: 0.0,
                routeName: "IncrementStable"
            )
            
            // Option 1: Increment v1 pair
            let pairV1 = getAccount(SwapStrategy.INCREMENT_V1_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            
            if pairV1 != nil {
                let v1Estimate = pairV1!.getAmountOut(
                    amountIn: amount,
                    tokenInKey: "A.d6f80565193ad727.stFlowToken"
                )
                
                bestQuote = RouteQuote(
                    route: SwapRoute.incrementV1,
                    expectedOutput: v1Estimate,
                    routeName: "IncrementV1"
                )
            }
            
            // Option 2: Increment stable pair
            let pairStable = getAccount(SwapStrategy.INCREMENT_STABLE_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
            
            if pairStable != nil {
                let stableEstimate = pairStable!.getAmountOut(
                    amountIn: amount,
                    tokenInKey: "A.d6f80565193ad727.stFlowToken"
                )
                
                if stableEstimate > bestQuote.expectedOutput {
                    bestQuote = RouteQuote(
                        route: SwapRoute.incrementStable,
                        expectedOutput: stableEstimate,
                        routeName: "IncrementStable"
                    )
                }
            }
            
            return bestQuote
        }
        
        // ====================================================================
        // SWAP EXECUTION FUNCTIONS
        // ====================================================================
        
        access(self) fun swapViaIncrementV1(from: @FlowToken.Vault): @stFlowToken.Vault {
            let pair = getAccount(SwapStrategy.INCREMENT_V1_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
                ?? panic("Cannot access Increment v1 pair")
            
            let result <- pair.swap(vaultIn: <-from, exactAmountOut: nil)
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "IncrementV1", amount: result.balance)
            
            return <- (result as! @stFlowToken.Vault)
        }
        
        access(self) fun swapViaIncrementStable(from: @FlowToken.Vault): @stFlowToken.Vault {
            let pair = getAccount(SwapStrategy.INCREMENT_STABLE_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
                ?? panic("Cannot access Increment stable pair")
            
            let result <- pair.swap(vaultIn: <-from, exactAmountOut: nil)
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "IncrementStable", amount: result.balance)
            
            return <- (result as! @stFlowToken.Vault)
        }
        
        access(self) fun swapViaRouter(from: @FlowToken.Vault): @stFlowToken.Vault {
            let deadline = getCurrentBlock().timestamp + 300.0
            
            let result <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-from,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.1654653399040a61.FlowToken",
                    "A.d6f80565193ad727.stFlowToken"
                ],
                deadline: deadline
            )
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "SwapRouter", amount: result.balance)
            
            return <- (result as! @stFlowToken.Vault)
        }
        
        access(self) fun swapStFlowViaIncrementV1(from: @stFlowToken.Vault): @FlowToken.Vault {
            let pair = getAccount(SwapStrategy.INCREMENT_V1_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
                ?? panic("Cannot access Increment v1 pair")
            
            let result <- pair.swap(vaultIn: <-from, exactAmountOut: nil)
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "IncrementV1", amount: result.balance)
            
            return <- (result as! @FlowToken.Vault)
        }
        
        access(self) fun swapStFlowViaIncrementStable(from: @stFlowToken.Vault): @FlowToken.Vault {
            let pair = getAccount(SwapStrategy.INCREMENT_STABLE_PAIR)
                .capabilities
                .borrow<&{SwapInterfaces.PairPublic}>(/public/increment_swap_pair)
                ?? panic("Cannot access Increment stable pair")
            
            let result <- pair.swap(vaultIn: <-from, exactAmountOut: nil)
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "IncrementStable", amount: result.balance)
            
            return <- (result as! @FlowToken.Vault)
        }
        
        access(self) fun swapStFlowViaRouter(from: @stFlowToken.Vault): @FlowToken.Vault {
            let deadline = getCurrentBlock().timestamp + 300.0
            
            let result <- SwapRouter.swapExactTokensForTokens(
                exactVaultIn: <-from,
                amountOutMin: 0.0,
                tokenKeyPath: [
                    "A.d6f80565193ad727.stFlowToken",
                    "A.1654653399040a61.FlowToken"
                ],
                deadline: deadline
            )
            
            SwapStrategy.totalSwaps = SwapStrategy.totalSwaps + 1
            SwapStrategy.trackVolume(pair: "SwapRouter", amount: result.balance)
            
            return <- (result as! @FlowToken.Vault)
        }
        
        /// Harvest - return accumulated tokens
        access(all) fun harvest(): @{FungibleToken.Vault} {
            // Return any accumulated FLOW
            let balance = self.flowVault.balance
            
            if balance > 0.0 {
                return <- self.flowVault.withdraw(amount: balance)
            } else {
                return <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
            }
        }
        
        /// Emergency exit - return all tokens
        access(all) fun emergencyExit(): @{FungibleToken.Vault} {
            let flowBalance = self.flowVault.balance
            
            if flowBalance > 0.0 {
                return <- self.flowVault.withdraw(amount: flowBalance)
            } else {
                return <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
            }
        }
        
        access(all) fun getBalances(): {String: UFix64} {
            return {
                "flow": self.flowVault.balance,
                "stflow": self.stFlowVault.balance
            }
        }
    }
    
    // ====================================================================
    // CONTRACT FUNCTIONS
    // ====================================================================
    access(all) fun createStrategy(): @Strategy {
        return <- create Strategy()
    }
    
    access(contract) fun trackVolume(pair: String, amount: UFix64) {
        if self.totalVolumeByPair[pair] == nil {
            self.totalVolumeByPair[pair] = 0.0
        }
        self.totalVolumeByPair[pair] = self.totalVolumeByPair[pair]! + amount
    }
    
    access(all) fun getMetrics(): {String: AnyStruct} {
        return {
            "totalSwaps": self.totalSwaps,
            "totalVolumeByPair": self.totalVolumeByPair
        }
    }
    
    /// Get swap quote for FLOW -> stFLOW
    access(all) fun getQuoteFlowToStFlow(amount: UFix64): RouteQuote {
        // Create temporary strategy to access quote function
        let tempStrategy <- create Strategy()
        let quote = tempStrategy.findOptimalRouteFlowToStFlow(amount: amount)
        destroy tempStrategy
        return quote
    }
    
    /// Get swap quote for stFLOW -> FLOW
    access(all) fun getQuoteStFlowToFlow(amount: UFix64): RouteQuote {
        let tempStrategy <- create Strategy()
        let quote = tempStrategy.findOptimalRouteStFlowToFlow(amount: amount)
        destroy tempStrategy
        return quote
    }
    
    // ====================================================================
    // INITIALIZATION
    // ====================================================================
    init() {
        self.INCREMENT_V1_PAIR = 0x396c0cda3302d8c5
        self.INCREMENT_STABLE_PAIR = 0xc353b9d685ec427d
        
        self.totalSwaps = 0
        self.totalVolumeByPair = {}
    }
}