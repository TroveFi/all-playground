// cadence/transactions/bridge_and_deposit_to_evm_vault.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import EVM from 0xe467b9dd11fa00df

// Bridge FLOW to EVM and deposit into your vault in one transaction
transaction(amount: UFix64, vaultAddress: String, riskLevel: UInt8) {
    let flowVault: auth(FungibleToken.Withdraw) &FlowToken.Vault
    let coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        // Get FLOW vault
        self.flowVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("Could not borrow FLOW vault")

        // Get or create COA
        if signer.storage.borrow<&EVM.CadenceOwnedAccount>(from: /storage/evm) == nil {
            let coa <- EVM.createCadenceOwnedAccount()
            signer.storage.save(<-coa, to: /storage/evm)
        }

        self.coa = signer.storage.borrow<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("Could not borrow COA")
    }

    execute {
        // 1. Withdraw FLOW from Cadence vault
        let flowToTransfer <- self.flowVault.withdraw(amount: amount)

        // 2. Deposit FLOW into COA (converts to native FLOW on EVM side)
        self.coa.deposit(from: <-flowToTransfer)

        // 3. Convert vault address string to EVM address
        let vaultAddressBytes = vaultAddress.slice(from: 2, upTo: vaultAddress.length).decodeHex()
        let vaultEVMAddress = EVM.EVMAddress(bytes: vaultAddressBytes)

        // 4. Call depositNativeFlow on your EVM vault
        let depositCallData = EVM.encodeABIWithSignature(
            "depositNativeFlow(address,uint8)",
            [self.coa.address(), riskLevel]
        )

        let result = self.coa.call(
            to: vaultEVMAddress,
            data: depositCallData,
            gasLimit: 500000,
            value: EVM.Balance(attoflow: amount * 1000000000000000000)
        )

        assert(result.status == EVM.Status.successful, message: "Vault deposit failed")

        log("Successfully bridged ".concat(amount.toString()).concat(" FLOW to EVM vault"))
    }
}

// cadence/transactions/withdraw_from_evm_vault_to_cadence.cdc
import FungibleToken from 0xf233dcee88fe0abe
import FlowToken from 0x1654653399040a61
import EVM from 0xe467b9dd11fa00df

// Withdraw from EVM vault and bridge back to Cadence
transaction(asset: String, amount: UFix64, vaultAddress: String) {
    let flowReceiver: &{FungibleToken.Receiver}
    let coa: auth(EVM.Owner) &EVM.CadenceOwnedAccount

    prepare(signer: auth(Storage, BorrowValue) &Account) {
        // Get FLOW receiver
        self.flowReceiver = signer.capabilities.get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver).borrow()
            ?? panic("Could not borrow FLOW receiver")

        // Get COA
        self.coa = signer.storage.borrow<auth(EVM.Owner) &EVM.CadenceOwnedAccount>(
            from: /storage/evm
        ) ?? panic("Could not borrow COA")
    }

    execute {
        // 1. Convert vault address to EVM address
        let vaultAddressBytes = vaultAddress.slice(from: 2, upTo: vaultAddress.length).decodeHex()
        let vaultEVMAddress = EVM.EVMAddress(bytes: vaultAddressBytes)

        // 2. First request withdrawal from vault (if needed)
        let requestWithdrawalData = EVM.encodeABIWithSignature("requestWithdrawal()", [])
        let requestResult = self.coa.call(
            to: vaultEVMAddress,
            data: requestWithdrawalData,
            gasLimit: 200000,
            value: EVM.Balance(attoflow: 0)
        )

        // 3. Call withdraw function on your EVM vault
        let assetAddressBytes = asset.slice(from: 2, upTo: asset.length).decodeHex()
        let assetEVMAddress = EVM.EVMAddress(bytes: assetAddressBytes)
        
        let withdrawCallData = EVM.encodeABIWithSignature(
            "withdraw(address,uint256,address)",
            [assetEVMAddress, amount * 1000000000000000000, self.coa.address()]
        )

        let result = self.coa.call(
            to: vaultEVMAddress,
            data: withdrawCallData,
            gasLimit: 500000,
            value: EVM.Balance(attoflow: 0)
        )

        assert(result.status == EVM.Status.successful, message: "Vault withdrawal failed")

        // 4. Withdraw native FLOW from COA back to Cadence
        let flowVault <- self.coa.withdraw(balance: EVM.Balance(attoflow: amount * 1000000000000000000))
        self.flowReceiver.deposit(from: <-flowVault)

        log("Successfully withdrew ".concat(amount.toString()).concat(" FLOW from EVM vault to Cadence"))
    }
}

// cadence/scripts/check_evm_vault_balance.cdc
import EVM from 0xe467b9dd11fa00df

access(all) struct VaultBalance {
    access(all) let totalShares: UInt256
    access(all) let totalDeposited: UInt256
    access(all) let riskLevel: UInt8
    access(all) let canWithdraw: Bool

    init(totalShares: UInt256, totalDeposited: UInt256, riskLevel: UInt8, canWithdraw: Bool) {
        self.totalShares = totalShares
        self.totalDeposited = totalDeposited
        self.riskLevel = riskLevel
        self.canWithdraw = canWithdraw
    }
}

access(all) fun main(userAddress: Address, vaultAddress: String): VaultBalance? {
    let account = getAccount(userAddress)
    
    if let coa = account.capabilities.get<&EVM.CadenceOwnedAccount>(/public/evm).borrow() {
        let vaultAddressBytes = vaultAddress.slice(from: 2, upTo: vaultAddress.length).decodeHex()
        let vaultEVMAddress = EVM.EVMAddress(bytes: vaultAddressBytes)
        
        // Call getUserPosition function
        let callData = EVM.encodeABIWithSignature(
            "getUserPosition(address)", 
            [coa.address()]
        )
        
        let result = coa.call(
            to: vaultEVMAddress,
            data: callData,
            gasLimit: 100000,
            value: EVM.Balance(attoflow: 0)
        )
        
        if result.status == EVM.Status.successful {
            // Decode the result to get position info
            // This would need proper ABI decoding - simplified here
            return VaultBalance(
                totalShares: 0,
                totalDeposited: 0, 
                riskLevel: 1,
                canWithdraw: false
            )
        }
    }
    
    return nil
}