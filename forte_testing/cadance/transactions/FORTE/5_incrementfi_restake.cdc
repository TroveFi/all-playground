import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import IncrementFiPoolLiquidityConnectors from 0x49bae091e5ea16b5
import IncrementFiSwapConnectors from 0x49bae091e5ea16b5
import SwapConnectors from 0xaddd594cf410166a
import DeFiActions from 0x4c2ff9dd03ab442f

// Transaction to test IncrementFi restake: claim rewards → zap to LP → restake
transaction(pid: UInt64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            pid >= 0: "Pool ID must be valid"
        }
        
        log("Starting IncrementFi restake test for pool: ".concat(pid.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Get initial stake amount for comparison
        let stakingConnector = IncrementFiStakingConnectors.PoolStakeManager(
            poolID: pid,
            uniqueID: operationID
        )
        
        let initialStake = stakingConnector.getStakedAmount(staker: signer.address)
        log("Initial stake: ".concat(initialStake.toString()))
        
        // Create rewards source
        let rewardsSource = IncrementFiStakingConnectors.PoolRewardsSource(
            poolID: pid,
            staker: signer.address,
            uniqueID: operationID
        )
        
        // Check available rewards
        let availableRewards = rewardsSource.getAvailable()
        log("Available rewards: ".concat(availableRewards.toString()))
        
        if availableRewards > 0.001 {
            // Create zapper for converting rewards to LP tokens
            let zapper = IncrementFiPoolLiquidityConnectors.Zapper(
                tokenInType: Type<@FlowToken.Vault>(),  // Assuming rewards in FLOW
                poolID: pid,
                uniqueID: operationID
            )
            
            // Create pool sink for restaking
            let poolSink = IncrementFiStakingConnectors.PoolSink(
                poolID: pid,
                staker: signer.address,
                uniqueID: operationID
            )
            
            // Get quote for LP output
            let zapQuote = zapper.quote(input: availableRewards)
            log("Expected LP out: ".concat(zapQuote.output.toString()))
            
            // Create swap source to chain rewards → zap → restake
            let swapSource = SwapConnectors.SwapSource(
                source: rewardsSource,
                swapper: zapper,
                sink: poolSink,
                uniqueID: operationID
            )
            
            // Execute the restake flow
            let result = swapSource.swap(
                input: availableRewards,
                minOutput: zapQuote.output * 0.95  // 5% slippage tolerance
            )
            
            log("Restake result output: ".concat(result.output.toString()))
            
            // Verify stake increased
            let finalStake = stakingConnector.getStakedAmount(staker: signer.address)
            log("Final stake: ".concat(finalStake.toString()))
            
            post {
                result.output > 0.0: "Restake must produce positive output"
                finalStake >= initialStake: "Stake amount should increase or stay same"
            }
            
            log("IncrementFi restake completed successfully")
        } else {
            log("No rewards available for restaking")
        }
    }
}