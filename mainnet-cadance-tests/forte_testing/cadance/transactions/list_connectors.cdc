import "FungibleTokenConnectors"
import "SwapConnectors" 
import "IncrementFiStakingConnectors"
import "IncrementFiSwapConnectors"
import "BandOracleConnectors"

access(all) fun main(): {String: String} {
    let connectors: {String: String} = {}
    
    // Test that connector contracts are available
    connectors["FungibleTokenConnectors"] = "Available"
    connectors["SwapConnectors"] = "Available"
    connectors["IncrementFiStakingConnectors"] = "Available"
    connectors["IncrementFiSwapConnectors"] = "Available" 
    connectors["BandOracleConnectors"] = "Available"
    
    return connectors
}