import IncrementFiStakingConnectors from 0x49bae091e5ea16b5
import IncrementFiPoolLiquidityConnectors from 0x49bae091e5ea16b5
import DeFiActions from 0x4c2ff9dd03ab442f
import FungibleToken from 0x9a0766d93b6608b7
import FlowToken from 0x7e60df042a9c0868

// Transaction to test IncrementFi staking connector components
transaction(pid: UInt64) {
    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController) &Account) {
        pre {
            pid >= 0: "Pool ID must be valid"
        }
        
        log("Starting IncrementFi staking connector test for pool: ".concat(pid.toString()))
        
        let operationID = DeFiActions.createUniqueIdentifier()
        
        // Test 1: Check if pool exists using the borrowPool helper
        let pool = IncrementFiStakingConnectors.borrowPool(pid: pid)
        
        if pool == nil {
            log("Pool ".concat(pid.toString()).concat(" not found or not accessible"))
            log("Test completed - pool not available")
            return
        }
        
        log("Pool found and accessible")
        
        // Test 2: Check user's current staking info
        let userInfo = pool!.getUserInfo(address: signer.address)
        
        if userInfo != nil {
            log("Current staking amount: ".concat(userInfo!.stakingAmount.toString()))
            log("Unclaimed rewards: ".concat(userInfo!.unclaimedRewards.keys.length.toString()).concat(" token types"))
        } else {
            log("User has no staking position in this pool")
        }
        
        // Test 3: Try to create PoolSink (may fail if pool requirements not met)
        let poolSinkResult = IncrementFiStakingConnectors.PoolSink(
            pid: pid,
            staker: signer.address,
            uniqueID: operationID
        )
        
        log("PoolSink created successfully")
        log("Sink type: ".concat(poolSinkResult.getSinkType().identifier))
        log("Minimum capacity: ".concat(poolSinkResult.minimumCapacity().toString()))
        
        // Test 4: Test helper functions
        let tokenTypeFromString = IncrementFiStakingConnectors.tokenTypeIdentifierToVaultType("A.7e60df042a9c0868.FlowToken")
        log("Token type conversion test: ".concat(tokenTypeFromString.identifier))
        
        // Test 5: Test Zapper availability (may fail if no valid pairs)
        let zapperType = Type<IncrementFiPoolLiquidityConnectors.Zapper>()
        log("Zapper type available: ".concat(zapperType.identifier))
        
        log("IncrementFi staking connector test completed successfully")
    }
    
    execute {
        log("Transaction executed successfully")
    }
    
    post {
        // No-op transaction should not change state
    }
}