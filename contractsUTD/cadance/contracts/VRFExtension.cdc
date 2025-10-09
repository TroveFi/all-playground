import VaultCore from 0x79f5b5b0f95a160b

access(all) contract VRFExtension {
    
    access(all) let CADENCE_ARCH_VRF: Address
    access(all) let BASIS_POINTS: UFix64
    access(all) let ExtensionStoragePath: StoragePath
    access(all) let ExtensionPublicPath: PublicPath
    
    access(all) event EpochAdvanced(epochNumber: UInt64, startTime: UFix64, yieldPool: UFix64)
    access(all) event RewardClaimed(user: Address, epoch: UInt64, won: Bool, baseYield: UFix64, actualPayout: UFix64, multiplier: UFix64)
    access(all) event VRFMultiplierSet(user: Address, multiplier: UFix64)
    access(all) event YieldAdded(amount: UFix64, epoch: UInt64)
    
    access(self) var currentEpoch: UInt64
    access(self) var epochDuration: UFix64
    access(self) var lastEpochStart: UFix64
    access(self) var epochsPerPayout: UInt64
    access(self) var totalYieldPool: UFix64
    access(self) var totalDistributed: UFix64
    
    access(all) struct VRFMultiplierOption {
        access(all) let multiplier: UFix64
        access(all) let probability: UFix64
        
        init(multiplier: UFix64, probability: UFix64) {
            self.multiplier = multiplier
            self.probability = probability
        }
    }
    
    access(all) struct EpochData {
        access(all) let epochNumber: UInt64
        access(all) let startTime: UFix64
        access(all) var endTime: UFix64
        access(all) var totalYieldPool: UFix64
        access(all) var totalDistributed: UFix64
        access(all) var participantCount: UInt64
        access(all) var finalized: Bool
        
        init(epochNumber: UInt64, startTime: UFix64) {
            self.epochNumber = epochNumber
            self.startTime = startTime
            self.endTime = startTime + VRFExtension.epochDuration
            self.totalYieldPool = 0.0
            self.totalDistributed = 0.0
            self.participantCount = 0
            self.finalized = false
        }
        
        access(contract) fun finalize() {
            self.finalized = true
            self.endTime = getCurrentBlock().timestamp
        }
        
        access(contract) fun addYield(amount: UFix64) {
            self.totalYieldPool = self.totalYieldPool + amount
        }
        
        access(contract) fun recordDistribution(amount: UFix64) {
            self.totalDistributed = self.totalDistributed + amount
        }
        
        access(contract) fun incrementParticipants() {
            self.participantCount = self.participantCount + 1
        }
    }
    
    access(all) struct UserEpochData {
        access(all) let user: Address
        access(all) let epoch: UInt64
        access(all) let vrfMultiplier: UFix64
        access(all) let depositAmount: UFix64
        access(all) let claimed: Bool
        access(all) let won: Bool
        access(all) let payoutAmount: UFix64
        
        init(user: Address, epoch: UInt64, vrfMultiplier: UFix64, depositAmount: UFix64, claimed: Bool, won: Bool, payoutAmount: UFix64) {
            self.user = user
            self.epoch = epoch
            self.vrfMultiplier = vrfMultiplier
            self.depositAmount = depositAmount
            self.claimed = claimed
            self.won = won
            self.payoutAmount = payoutAmount
        }
    }
    
    access(all) resource Extension {
        access(self) let vaultCap: Capability<&VaultCore.Vault>
        access(self) let epochs: {UInt64: EpochData}
        access(self) let userEpochData: {Address: {UInt64: UserEpochData}}
        access(self) let vrfMultipliers: {UFix64: VRFMultiplierOption}
        
        init(vaultCap: Capability<&VaultCore.Vault>) {
            self.vaultCap = vaultCap
            self.epochs = {}
            self.userEpochData = {}
            self.vrfMultipliers = {}
            
            self.epochs[VRFExtension.currentEpoch] = EpochData(
                epochNumber: VRFExtension.currentEpoch,
                startTime: VRFExtension.lastEpochStart
            )
            
            self.initializeVRFMultipliers()
        }
        
        access(self) fun initializeVRFMultipliers() {
            self.vrfMultipliers[1.0] = VRFMultiplierOption(multiplier: 1.0, probability: 10000.0)
            self.vrfMultipliers[2.0] = VRFMultiplierOption(multiplier: 2.0, probability: 5000.0)
            self.vrfMultipliers[5.0] = VRFMultiplierOption(multiplier: 5.0, probability: 2000.0)
            self.vrfMultipliers[10.0] = VRFMultiplierOption(multiplier: 10.0, probability: 1000.0)
            self.vrfMultipliers[50.0] = VRFMultiplierOption(multiplier: 50.0, probability: 200.0)
            self.vrfMultipliers[100.0] = VRFMultiplierOption(multiplier: 100.0, probability: 100.0)
        }
        
        access(all) fun advanceEpoch() {
            self.epochs[VRFExtension.currentEpoch]!.finalize()
            VRFExtension.currentEpoch = VRFExtension.currentEpoch + 1
            VRFExtension.lastEpochStart = getCurrentBlock().timestamp
            
            self.epochs[VRFExtension.currentEpoch] = EpochData(
                epochNumber: VRFExtension.currentEpoch,
                startTime: VRFExtension.lastEpochStart
            )
            
            emit EpochAdvanced(epochNumber: VRFExtension.currentEpoch, startTime: VRFExtension.lastEpochStart, yieldPool: VRFExtension.totalYieldPool)
        }
        
        access(all) fun addYield(amount: UFix64) {
            pre {
                amount > 0.0: "Amount must be positive"
            }
            
            VRFExtension.totalYieldPool = VRFExtension.totalYieldPool + amount
            self.epochs[VRFExtension.currentEpoch]!.addYield(amount: amount)
            emit YieldAdded(amount: amount, epoch: VRFExtension.currentEpoch)
        }
        
        access(all) fun setUserVRFMultiplier(user: Address, multiplier: UFix64) {
            pre {
                self.vrfMultipliers[multiplier] != nil: "Invalid multiplier"
            }
            
            let vault = self.vaultCap.borrow() ?? panic("Cannot borrow vault")
            vault.setUserVRFMultiplier(user: user, multiplier: multiplier)
            emit VRFMultiplierSet(user: user, multiplier: multiplier)
        }
        
        access(all) fun recordUserDeposit(user: Address, amount: UFix64, vrfMultiplier: UFix64) {
            let eligibilityEpoch = VRFExtension.currentEpoch + VRFExtension.epochsPerPayout
            
            if self.userEpochData[user] == nil {
                self.userEpochData[user] = {}
            }
            
            if self.userEpochData[user]![eligibilityEpoch] == nil {
                self.userEpochData[user]!.insert(key: eligibilityEpoch, UserEpochData(
                    user: user,
                    epoch: eligibilityEpoch,
                    vrfMultiplier: vrfMultiplier,
                    depositAmount: amount,
                    claimed: false,
                    won: false,
                    payoutAmount: 0.0
                ))
                
                if self.epochs[eligibilityEpoch] == nil {
                    self.epochs[eligibilityEpoch] = EpochData(
                        epochNumber: eligibilityEpoch,
                        startTime: VRFExtension.lastEpochStart + (UFix64(eligibilityEpoch - VRFExtension.currentEpoch) * VRFExtension.epochDuration)
                    )
                }
                
                self.epochs[eligibilityEpoch]!.incrementParticipants()
            } else {
                let existing = self.userEpochData[user]![eligibilityEpoch]!
                self.userEpochData[user]!.insert(key: eligibilityEpoch, UserEpochData(
                    user: existing.user,
                    epoch: existing.epoch,
                    vrfMultiplier: existing.vrfMultiplier,
                    depositAmount: existing.depositAmount + amount,
                    claimed: existing.claimed,
                    won: existing.won,
                    payoutAmount: existing.payoutAmount
                ))
            }
        }
        
        access(all) fun claimReward(user: Address, epochNumber: UInt64): {String: UFix64} {
            pre {
                epochNumber < VRFExtension.currentEpoch: "Epoch not completed"
                epochNumber % VRFExtension.epochsPerPayout == 0: "Not a payout epoch"
                self.userEpochData[user] != nil: "User not found"
                self.userEpochData[user]![epochNumber] != nil: "Not eligible for this epoch"
                !self.userEpochData[user]![epochNumber]!.claimed: "Already claimed"
            }
            
            let vault = self.vaultCap.borrow() ?? panic("Cannot borrow vault")
            let userPosition = vault.getUserPosition(user: user) ?? panic("No user position")
            
            assert(userPosition.yieldEligible, message: "Not yield eligible")
            
            let userData = self.userEpochData[user]![epochNumber]!
            let epochData = self.epochs[epochNumber]!
            
            let baseYield = epochData.participantCount > 0 
                ? epochData.totalYieldPool / UFix64(epochData.participantCount)
                : 0.0
            
            let multiplierOption = self.vrfMultipliers[userData.vrfMultiplier]!
            
            let blockHeight = getCurrentBlock().height
            let timestamp = getCurrentBlock().timestamp
            let randomSeed = UInt64(blockHeight) * 1000000 + UInt64(timestamp)
            let normalizedRandom = randomSeed % UInt64(VRFExtension.BASIS_POINTS)
            let won = UFix64(normalizedRandom) < multiplierOption.probability
            
            var actualPayout = 0.0
            
            if won {
                let potentialPayout = baseYield * multiplierOption.multiplier
                let availableYield = epochData.totalYieldPool - epochData.totalDistributed
                
                actualPayout = potentialPayout < availableYield ? potentialPayout : availableYield
                
                if actualPayout > 0.0 {
                    self.epochs[epochNumber]!.recordDistribution(amount: actualPayout)
                    VRFExtension.totalYieldPool = VRFExtension.totalYieldPool - actualPayout
                    VRFExtension.totalDistributed = VRFExtension.totalDistributed + actualPayout
                }
            }
            
            self.userEpochData[user]!.insert(key: epochNumber, UserEpochData(
                user: userData.user,
                epoch: userData.epoch,
                vrfMultiplier: userData.vrfMultiplier,
                depositAmount: userData.depositAmount,
                claimed: true,
                won: won,
                payoutAmount: actualPayout
            ))
            
            emit RewardClaimed(user: user, epoch: epochNumber, won: won, baseYield: baseYield, actualPayout: actualPayout, multiplier: userData.vrfMultiplier)
            
            return {
                "won": won ? 1.0 : 0.0,
                "baseYield": baseYield,
                "actualPayout": actualPayout,
                "multiplier": userData.vrfMultiplier,
                "winProbability": multiplierOption.probability
            }
        }
        
        access(all) fun getEpochInfo(epochNumber: UInt64): EpochData? {
            return self.epochs[epochNumber]
        }
        
        access(all) fun getUserEpochData(user: Address, epochNumber: UInt64): UserEpochData? {
            if self.userEpochData[user] == nil {
                return nil
            }
            return self.userEpochData[user]![epochNumber]
        }
        
        access(all) fun getClaimableEpochs(user: Address): [UInt64] {
            let claimable: [UInt64] = []
            
            if self.userEpochData[user] == nil {
                return claimable
            }
            
            var epoch = VRFExtension.epochsPerPayout
            while epoch < VRFExtension.currentEpoch {
                if self.userEpochData[user]![epoch] != nil && !self.userEpochData[user]![epoch]!.claimed {
                    claimable.append(epoch)
                }
                epoch = epoch + VRFExtension.epochsPerPayout
            }
            
            return claimable
        }
        
        access(all) fun getAvailableMultipliers(): [VRFMultiplierOption] {
            return [
                self.vrfMultipliers[1.0]!,
                self.vrfMultipliers[2.0]!,
                self.vrfMultipliers[5.0]!,
                self.vrfMultipliers[10.0]!,
                self.vrfMultipliers[50.0]!,
                self.vrfMultipliers[100.0]!
            ]
        }
        
        access(all) fun getCurrentEpochStatus(): {String: AnyStruct} {
            let endTime = VRFExtension.lastEpochStart + VRFExtension.epochDuration
            let timeRemaining = getCurrentBlock().timestamp < endTime ? endTime - getCurrentBlock().timestamp : 0.0
            
            return {
                "currentEpoch": VRFExtension.currentEpoch,
                "timeRemaining": timeRemaining,
                "yieldPool": VRFExtension.totalYieldPool,
                "totalDistributed": VRFExtension.totalDistributed,
                "epochDuration": VRFExtension.epochDuration,
                "epochsPerPayout": VRFExtension.epochsPerPayout
            }
        }
    }
    
    access(all) fun createExtension(vaultCap: Capability<&VaultCore.Vault>): @Extension {
        return <- create Extension(vaultCap: vaultCap)
    }
    
    access(all) fun getMetrics(): {String: AnyStruct} {
        return {
            "currentEpoch": self.currentEpoch,
            "epochDuration": self.epochDuration,
            "epochsPerPayout": self.epochsPerPayout,
            "totalYieldPool": self.totalYieldPool,
            "totalDistributed": self.totalDistributed
        }
    }
    
    init() {
        self.ExtensionStoragePath = /storage/VRFExtension
        self.ExtensionPublicPath = /public/VRFExtension
        self.CADENCE_ARCH_VRF = 0xe467b9dd11fa00df
        self.BASIS_POINTS = 10000.0
        self.currentEpoch = 1
        self.epochDuration = 604800.0
        self.lastEpochStart = getCurrentBlock().timestamp
        self.epochsPerPayout = 4
        self.totalYieldPool = 0.0
        self.totalDistributed = 0.0
    }
}