// 1. setup-action-router.cdc
// This transaction sets up the ActionRouter after deployment

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

transaction {
    prepare(admin: &Account) {
        let adminRef = admin.storage.borrow<&ActionRouter.Admin>(from: ActionRouter.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        // Set initial configuration
        adminRef.updateLimits(minStake: 1.0, maxStake: 10000.0, maxOpsPerBlock: 10)
        adminRef.setActive(active: true)
        
        log("ActionRouter configured successfully")
    }
}

// 2. authorize-evm-caller.cdc  
// This transaction authorizes an EVM address to call the router

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

transaction(evmAddress: Address) {
    prepare(admin: &Account) {
        let adminRef = admin.storage.borrow<&ActionRouter.Admin>(from: ActionRouter.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        adminRef.authorizeEVMCaller(caller: evmAddress)
        
        log("EVM caller authorized: ".concat(evmAddress.toString()))
    }
}

// 3. fund-router.cdc
// This transaction funds the router with FLOW tokens

import FlowToken from 0x1654653399040a61

transaction(amount: UFix64, routerAddress: Address) {
    let flowVault: &FlowToken.Vault
    
    prepare(signer: &Account) {
        self.flowVault = signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken vault")
    }
    
    execute {
        let flowToTransfer <- self.flowVault.withdraw(amount: amount)
        
        let routerAccount = getAccount(routerAddress)
        let routerFlowReceiver = routerAccount.capabilities.get<&{FlowToken.Receiver}>(/public/flowTokenReceiver).borrow()
            ?? panic("Could not borrow router FlowToken receiver")
        
        routerFlowReceiver.deposit(from: <-flowToTransfer)
        
        log("Funded router with ".concat(amount.toString()).concat(" FLOW"))
    }
}

// 4. check-router-status.cdc
// This script checks the router status

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

access(all) fun main(routerAddress: Address): RouterStats {
    let routerAccount = getAccount(routerAddress)
    
    let stats = ActionRouter.getStats()
    
    log("Router Stats:")
    log("  Total Stake Operations: ".concat(stats.totalStakeOps.toString()))
    log("  Total Unstake Operations: ".concat(stats.totalUnstakeOps.toString()))
    log("  Total FLOW Staked: ".concat(stats.totalFlowStaked.toString()))
    log("  Total stFLOW Minted: ".concat(stats.totalStFlowMinted.toString()))
    log("  Current FLOW Balance: ".concat(stats.currentFlowBalance.toString()))
    log("  Current stFLOW Balance: ".concat(stats.currentStFlowBalance.toString()))
    log("  Router Active: ".concat(stats.isActive.toString()))
    
    return stats
}

// 5. test-stake.cdc
// This transaction tests staking functionality

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

transaction(amount: UFix64, evmAddress: Address) {
    prepare(signer: &Account) {
        // This would normally be called by the cross-VM bridge, not directly
        // But can be used for testing
        
        let result = ActionRouter.stakeFlow(
            amount: amount,
            recipient: evmAddress,
            requestId: "test-".concat(getCurrentBlock().height.toString())
        )
        
        log("Stake result:")
        log("  FLOW Amount: ".concat(result.flowAmount.toString()))
        log("  stFLOW Received: ".concat(result.stFlowReceived.toString()))
        log("  Exchange Rate: ".concat(result.exchangeRate.toString()))
        log("  Success: ".concat(result.success.toString()))
    }
}

// 6. get-exchange-rate.cdc
// This script gets the current exchange rate

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

access(all) fun main(): UFix64 {
    let exchangeRate = ActionRouter.getExchangeRate()
    log("Current stFLOW exchange rate: ".concat(exchangeRate.toString()))
    return exchangeRate
}

// 7. emergency-withdraw.cdc
// Emergency withdrawal transaction

import ActionRouter from 0xYOUR_ACCOUNT_ADDRESS

transaction(amount: UFix64, recipient: Address) {
    prepare(admin: &Account) {
        let adminRef = admin.storage.borrow<&ActionRouter.Admin>(from: ActionRouter.AdminStoragePath)
            ?? panic("Could not borrow admin reference")
        
        adminRef.emergencyWithdraw(amount: amount, recipient: recipient)
        
        log("Emergency withdrawal of ".concat(amount.toString()).concat(" FLOW to ").concat(recipient.toString()))
    }
}