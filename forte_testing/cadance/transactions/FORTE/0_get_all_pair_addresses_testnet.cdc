import SwapFactory from 0x6ca93d49c45a249f

access(all) fun main(): [Address] {
    let total: Int = SwapFactory.getAllPairsLength()
    if total <= 0 { return [] }

    let from: UInt64 = 0
    let to: UInt64 = UInt64(total) // upper bound (exclusive)
    return SwapFactory.getSlicedPairs(from: from, to: to)
}
