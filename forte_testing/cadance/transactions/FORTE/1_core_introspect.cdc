import DeFiActions from 0x4c2ff9dd03ab442f
import DeFiActionsUtils from 0x4c2ff9dd03ab442f

// Script to introspect DeFi Actions core components and interfaces
access(all) fun main(): {String: String} {
    let result: {String: String} = {}
    
    // Core primitive interfaces
    result["Source"] = Type<{DeFiActions.Source}>().identifier
    result["Sink"] = Type<{DeFiActions.Sink}>().identifier
    result["Swapper"] = Type<{DeFiActions.Swapper}>().identifier
    result["PriceOracle"] = Type<{DeFiActions.PriceOracle}>().identifier
    result["Flasher"] = Type<{DeFiActions.Flasher}>().identifier
    
    // Helper structs
    result["Quote"] = Type<DeFiActions.Quote>().identifier
    result["UniqueIdentifier"] = Type<DeFiActionsUtils.UniqueIdentifier>().identifier
    result["ComponentInfo"] = Type<DeFiActions.ComponentInfo>().identifier
    
    // Additional core types
    result["Action"] = Type<{DeFiActions.Action}>().identifier
    result["ActionResult"] = Type<DeFiActions.ActionResult>().identifier
    
    return result
}