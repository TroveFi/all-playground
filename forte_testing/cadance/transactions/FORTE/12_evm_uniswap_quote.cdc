import UniswapV2SwapConnectors from 0xfef8e4c5c16ccda5
import EVM from 0x8c5303eaa26202d6
import DeFiActions from 0x4c2ff9dd03ab442f
import FlowToken from 0x7e60df042a9c0868

// Script to explore UniswapV2 EVM connector capabilities
access(all) fun main(routerAddressHex: String, tokenInAddressHex: String, tokenOutAddressHex: String): {String: AnyStruct} {
    log("Exploring UniswapV2 EVM connector capabilities")
    log("Router Address: ".concat(routerAddressHex))
    log("Token In Address: ".concat(tokenInAddressHex))
    log("Token Out Address: ".concat(tokenOutAddressHex))
    
    // Convert hex strings to EVM addresses to validate format
    let routerAddress = EVM.addressFromString(routerAddressHex)
    let tokenInAddress = EVM.addressFromString(tokenInAddressHex)
    let tokenOutAddress = EVM.addressFromString(tokenOutAddressHex)
    
    // Create a simple swap path
    let swapPath: [EVM.EVMAddress] = [tokenInAddress, tokenOutAddress]
    
    let result: {String: AnyStruct} = {
        "routerAddressHex": routerAddressHex,
        "tokenInAddressHex": tokenInAddressHex,
        "tokenOutAddressHex": tokenOutAddressHex,
        "routerEVMAddress": routerAddress.toString(),
        "tokenInEVMAddress": tokenInAddress.toString(),
        "tokenOutEVMAddress": tokenOutAddress.toString(),
        "swapPathLength": swapPath.length,
        "contractAvailable": true,
        "note": "UniswapV2SwapConnectors.Swapper requires COA capability - cannot create actual swapper in script context",
        "timestamp": getCurrentBlock().timestamp,
        "source": "UniswapV2_FlowEVM"
    }
    
    log("Contract import successful")
    log("EVM address conversion successful")
    log("Path length: ".concat(swapPath.length.toString()))
    
    return result
}