// 5. test-stake.cdc
// This transaction tests staking functionality

import ActionRouter from 0x79f5b5b0f95a160b

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