import LendingInterfaces from 0x2df970b6cdee5735
import LendingComptroller from 0xf80cb737bfe7c792
import LendingConfig from 0x2df970b6cdee5735

access(all) struct MarketInfo {
    access(all) let poolAddress: Address
    access(all) let tokenType: String
    access(all) let totalSupply: String
    access(all) let totalBorrow: String
    access(all) let supplyAPR: String
    access(all) let borrowAPR: String
    access(all) let collateralFactor: String
    access(all) let isOpen: Bool
    
    init(
        poolAddress: Address,
        tokenType: String,
        totalSupply: String,
        totalBorrow: String,
        supplyAPR: String,
        borrowAPR: String,
        collateralFactor: String,
        isOpen: Bool
    ) {
        self.poolAddress = poolAddress
        self.tokenType = tokenType
        self.totalSupply = totalSupply
        self.totalBorrow = totalBorrow
        self.supplyAPR = supplyAPR
        self.borrowAPR = borrowAPR
        self.collateralFactor = collateralFactor
        self.isOpen = isOpen
    }
}

access(all) fun main(): [MarketInfo] {
    let comptroller = getAccount(0xf80cb737bfe7c792).capabilities
        .borrow<&{LendingInterfaces.ComptrollerPublic}>(LendingConfig.ComptrollerPublicPath)
        ?? panic("Cannot access comptroller")
    
    let allMarkets = comptroller.getAllMarkets()
    let markets: [MarketInfo] = []
    
    for poolAddr in allMarkets {
        let marketInfo = comptroller.getMarketInfo(poolAddr: poolAddr)
        
        markets.append(MarketInfo(
            poolAddress: poolAddr,
            tokenType: marketInfo["marketType"]! as! String,
            totalSupply: marketInfo["marketSupplyScaled"]! as! String,
            totalBorrow: marketInfo["marketBorrowScaled"]! as! String,
            supplyAPR: marketInfo["marketSupplyApr"]! as! String,
            borrowAPR: marketInfo["marketBorrowApr"]! as! String,
            collateralFactor: marketInfo["marketCollateralFactor"]! as! String,
            isOpen: marketInfo["isOpen"]! as! Bool
        ))
    }
    
    return markets
}