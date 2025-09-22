import DeFiActions from 0x4c2ff9dd03ab442f

// Script to introspect DeFi Actions core components and interfaces
access(all) fun main(): {String: String} {
    let result: {String: String} = {}
    
    // Core primitive interfaces - only the essential ones
    result["Source"] = Type<{DeFiActions.Source}>().identifier
    result["Sink"] = Type<{DeFiActions.Sink}>().identifier
    result["Swapper"] = Type<{DeFiActions.Swapper}>().identifier
    result["PriceOracle"] = Type<{DeFiActions.PriceOracle}>().identifier
    result["Flasher"] = Type<{DeFiActions.Flasher}>().identifier
    
    // Core struct types
    result["UniqueIdentifier"] = Type<DeFiActions.UniqueIdentifier>().identifier
    result["ComponentInfo"] = Type<DeFiActions.ComponentInfo>().identifier
    
    // Struct interfaces
    result["IdentifiableStruct"] = Type<{DeFiActions.IdentifiableStruct}>().identifier
    result["Quote"] = Type<{DeFiActions.Quote}>().identifier
    
    // Resource types
    result["AuthenticationToken"] = Type<@DeFiActions.AuthenticationToken>().identifier
    
    // Current ID counter
    result["currentID"] = DeFiActions.currentID.toString()
    
    return result
}