import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868
import SwapRouter from 0x2f8af5ed05bbde0d
import SwapFactory from 0x6ca93d49c45a249f
import SwapConfig from 0x8d5b9dd833e176da
import SwapInterfaces from 0x8d5b9dd833e176da

// Minimal Working Arbitrage Bot
transaction(minProfitThreshold: UFix64, maxTradeSize: UFix64, emergencyStop: Bool) {
    
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        
        log("Starting arbitrage bot...")
        
        if emergencyStop {
            log("Emergency stop activated")
            return
        }
        
        let flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken vault")
        
        let currentBalance = flowVault.balance
        log("Current balance: ".concat(currentBalance.toString()).concat(" FLOW"))
        
        if currentBalance < 3.0 {
            log("Insufficient funds - need at least 3 FLOW")
            return
        }
        
        let flowTokenKey = "A.7e60df042a9c0868.FlowToken"
        let fusdTokenKey = "A.e223d8a629e49c68.FUSD"
        
        // Check if pair exists
        let pairAddress = SwapFactory.getPairAddress(token0Key: flowTokenKey, token1Key: fusdTokenKey)
        
        if pairAddress == nil {
            log("FLOW/FUSD pair not found")
            return
        }
        
        log("Found pair at: ".concat(pairAddress!.toString()))
        
        // Get pair reference using correct API
        let pairRef = getAccount(pairAddress!).capabilities.get<&{SwapInterfaces.PairPublic}>(SwapConfig.PairPublicPath).borrow()
        
        if pairRef == nil {
            log("Could not access pair contract")
            return
        }
        
        // Get reserves
        let pairInfo = pairRef!.getPairInfo()
        let token0Reserve = pairInfo[2] as! UFix64
        let token1Reserve = pairInfo[3] as! UFix64
        
        log("Reserves - Token0: ".concat(token0Reserve.toString()).concat(", Token1: ".concat(token1Reserve.toString())))
        
        if token0Reserve < 50.0 || token1Reserve < 50.0 {
            log("Insufficient liquidity for trading")
            return
        }
        
        // Simple arbitrage test: small round-trip trade
        let testAmount: UFix64 = 1.0
        
        // Calculate FLOW -> FUSD
        let fusdOut = SwapConfig.getAmountOutVolatile(
            amountIn: testAmount,
            reserveIn: token0Reserve,
            reserveOut: token1Reserve,
            swapFeeRateBps: 30
        )
        
        // Calculate FUSD -> FLOW
        let flowBack = SwapConfig.getAmountOutVolatile(
            amountIn: fusdOut,
            reserveIn: token1Reserve,
            reserveOut: token0Reserve,
            swapFeeRateBps: 30
        )
        
        let loss = testAmount - flowBack
        let lossPercent = (loss / testAmount) * 100.0
        
        log("Round-trip test: ".concat(lossPercent.toString()).concat("% loss"))
        
        // Expected loss is ~0.6% from fees. If significantly different, there may be opportunity
        let expectedLoss: UFix64 = 0.6
        let opportunity = lossPercent < expectedLoss ? expectedLoss - lossPercent : lossPercent - expectedLoss
        
        log("Market opportunity: ".concat(opportunity.toString()).concat("%"))
        
        if opportunity >= minProfitThreshold {
            
            log("Profitable opportunity detected!")
            
            var positionSize = maxTradeSize
            if positionSize > currentBalance * 0.5 {
                positionSize = currentBalance * 0.5
            }
            if positionSize > 5.0 {
                positionSize = 5.0  // Testnet limit
            }
            
            log("Position size: ".concat(positionSize.toString()).concat(" FLOW"))
            
            if positionSize >= 1.0 {
                
                log("Executing arbitrage trade...")
                
                let startBalance = flowVault.balance
                let tradeTokens <- flowVault.withdraw(amount: positionSize)
                let tradeAmount = tradeTokens.balance
                
                log("Trading ".concat(tradeAmount.toString()).concat(" FLOW"))
                
                // Step 1: FLOW -> FUSD
                let path1 = [flowTokenKey, fusdTokenKey]
                let expectedOut1 = SwapRouter.getAmountsOut(amountIn: tradeAmount, tokenKeyPath: path1)
                
                if expectedOut1.length >= 2 {
                    let minOut1 = expectedOut1[1] * 0.99
                    
                    let fusdVault <- SwapRouter.swapExactTokensForTokens(
                        exactVaultIn: <-tradeTokens,
                        amountOutMin: minOut1,
                        tokenKeyPath: path1,
                        deadline: getCurrentBlock().timestamp + 300.0
                    )
                    
                    let fusdAmount = fusdVault.balance
                    log("Got ".concat(fusdAmount.toString()).concat(" FUSD"))
                    
                    // Step 2: FUSD -> FLOW
                    let path2 = [fusdTokenKey, flowTokenKey]
                    let expectedOut2 = SwapRouter.getAmountsOut(amountIn: fusdAmount, tokenKeyPath: path2)
                    
                    if expectedOut2.length >= 2 {
                        let minOut2 = expectedOut2[1] * 0.99
                        
                        let finalVault <- SwapRouter.swapExactTokensForTokens(
                            exactVaultIn: <-fusdVault,
                            amountOutMin: minOut2,
                            tokenKeyPath: path2,
                            deadline: getCurrentBlock().timestamp + 300.0
                        )
                        
                        let finalAmount = finalVault.balance
                        log("Final amount: ".concat(finalAmount.toString()).concat(" FLOW"))
                        
                        flowVault.deposit(from: <-finalVault)
                        
                        let endBalance = flowVault.balance
                        let profit = endBalance > startBalance ? endBalance - startBalance : 0.0
                        let loss = startBalance > endBalance ? startBalance - endBalance : 0.0
                        
                        if profit > 0.0 {
                            log("PROFIT: ".concat(profit.toString()).concat(" FLOW"))
                        } else {
                            log("LOSS: ".concat(loss.toString()).concat(" FLOW"))
                        }
                        
                    } else {
                        log("Error calculating second swap")
                        destroy fusdVault
                    }
                    
                } else {
                    log("Error calculating first swap")
                    flowVault.deposit(from: <-tradeTokens)
                }
                
            } else {
                log("Position too small to execute")
            }
            
        } else {
            log("No profitable opportunity found")
        }
        
        let finalBalance = flowVault.balance
        log("Final balance: ".concat(finalBalance.toString()).concat(" FLOW"))
        log("Arbitrage cycle complete")
    }
}