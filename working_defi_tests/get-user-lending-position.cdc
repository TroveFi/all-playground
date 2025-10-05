import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

access(all) struct UserPosition {
    access(all) let poolAddress: Address
    access(all) let tokenType: String
    access(all) let supplyBalance: String
    access(all) let borrowBalance: String
    
    init(poolAddress: Address, tokenType: String, supplyBalance: String, borrowBalance: String) {
        self.poolAddress = poolAddress
        self.tokenType = tokenType
        self.supplyBalance = supplyBalance
        self.borrowBalance = borrowBalance
    }
}

access(all) fun main(userAddress: Address): {String: AnyStruct} {
    let comptroller = getAccount(0xf80cb737bfe7c792).capabilities
        .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
        ?? panic("Cannot access comptroller")
    
    let userMarkets = comptroller.getUserMarkets(userAddr: userAddress)
    let liquidity = comptroller.getUserCrossMarketLiquidity(userAddr: userAddress)
    
    let positions: [UserPosition] = []
    for poolAddr in userMarkets {
        let marketInfo = comptroller.getMarketInfo(poolAddr: poolAddr)
        let userMarketInfo = comptroller.getUserMarketInfo(userAddr: userAddress, poolAddr: poolAddr)
        
        positions.append(UserPosition(
            poolAddress: poolAddr,
            tokenType: marketInfo["marketType"]! as! String,
            supplyBalance: userMarketInfo["userSupplyScaled"]! as! String,
            borrowBalance: userMarketInfo["userBorrowScaled"]! as! String
        ))
    }
    
    return {
        "positions": positions,
        "totalCollateralUSD": liquidity[0],
        "totalBorrowUSD": liquidity[1],
        "totalSupplyUSD": liquidity[2]
    }
}