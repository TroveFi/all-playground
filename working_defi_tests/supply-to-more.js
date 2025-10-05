const { ethers } = require("hardhat");

async function main() {
    console.log("SUPPLYING ASSETS TO MORE MARKETS");
    console.log("================================");
    
    const [deployer] = await ethers.getSigners();
    console.log(`Account: ${deployer.address}`);
    
    // Contract addresses
    const POOL_PROXY = "0xbC92aaC2DBBF42215248B5688eB3D3d2b32F2c8d";
    const POOL_DATA_PROVIDER = "0x79e71e3c0EDF2B88b0aB38E9A1eF0F6a230e56bf";
    
    // Token addresses
    const TOKENS = {
        "WFLOW": "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e",
        "stgUSDC": "0xF1815bd50389c46847f0Bda824eC8da914045D14", 
        "USDF": "0x2aaBea2058b5aC2D339b163C6Ab6f2b6d53aabED",
        "ankrFLOWEVM": "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb",
        "cbBTC": "0xA0197b2044D28b08Be34d98b23c9312158Ea9A18"
    };
    
    // CONFIGURATION - MODIFY THESE VALUES
    const ASSET_TO_SUPPLY = "stgUSDC";
    const AMOUNT_TO_SUPPLY = "1";
    // END CONFIGURATION
    
    const ASSET_ADDRESS = TOKENS[ASSET_TO_SUPPLY];
    if (!ASSET_ADDRESS) {
        throw new Error(`Asset ${ASSET_TO_SUPPLY} not found`);
    }
    
    console.log(`Asset: ${ASSET_TO_SUPPLY}`);
    console.log(`Address: ${ASSET_ADDRESS}`);
    console.log(`Amount: ${AMOUNT_TO_SUPPLY}`);
    
    try {
        // STEP 1: Get token contract and check decimals
        console.log("\nSTEP 1: CHECKING TOKEN");
        console.log("======================");
        
        const token = await ethers.getContractAt([
            {
                "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
                "name": "balanceOf",
                "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [],
                "name": "decimals",
                "outputs": [{"internalType": "uint8", "name": "", "type": "uint8"}],
                "stateMutability": "view",
                "type": "function"
            },
            {
                "inputs": [
                    {"internalType": "address", "name": "spender", "type": "address"},
                    {"internalType": "uint256", "name": "amount", "type": "uint256"}
                ],
                "name": "approve",
                "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
                "stateMutability": "nonpayable",
                "type": "function"
            },
            {
                "inputs": [
                    {"internalType": "address", "name": "owner", "type": "address"},
                    {"internalType": "address", "name": "spender", "type": "address"}
                ],
                "name": "allowance",
                "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            }
        ], ASSET_ADDRESS);
        
        let decimals;
        try {
            decimals = await token.decimals();
        } catch (e) {
            // Fallback for tokens without decimals function
            if (ASSET_TO_SUPPLY === "stgUSDC" || ASSET_TO_SUPPLY === "USDF") {
                decimals = 6;
            } else {
                decimals = 18;
            }
            console.log(`Warning: Could not read decimals, using ${decimals}`);
        }
        
        console.log(`Decimals: ${decimals}`);
        
        // STEP 2: Check balance
        console.log("\nSTEP 2: CHECKING BALANCE");
        console.log("========================");
        
        const balance = await token.balanceOf(deployer.address);
        const balanceFormatted = ethers.formatUnits(balance, decimals);
        console.log(`Your ${ASSET_TO_SUPPLY} balance: ${balanceFormatted}`);
        
        const amountToSupply = ethers.parseUnits(AMOUNT_TO_SUPPLY, decimals);
        console.log(`Amount to supply: ${AMOUNT_TO_SUPPLY} ${ASSET_TO_SUPPLY}`);
        
        if (balance < amountToSupply) {
            throw new Error(`Insufficient balance. Have: ${balanceFormatted}, Need: ${AMOUNT_TO_SUPPLY}`);
        }
        
        // STEP 3: Check and set allowance
        console.log("\nSTEP 3: CHECKING ALLOWANCE");
        console.log("==========================");
        
        const currentAllowance = await token.allowance(deployer.address, POOL_PROXY);
        const allowanceFormatted = ethers.formatUnits(currentAllowance, decimals);
        console.log(`Current allowance: ${allowanceFormatted}`);
        
        if (currentAllowance < amountToSupply) {
            console.log("Need to approve...");
            
            // Approve a large amount for future transactions
            const approvalAmount = ethers.parseUnits("1000000", decimals);
            console.log(`Approving ${ethers.formatUnits(approvalAmount, decimals)} ${ASSET_TO_SUPPLY}...`);
            
            const approveTx = await token.approve(POOL_PROXY, approvalAmount);
            console.log(`Approval tx: ${approveTx.hash}`);
            
            console.log("Waiting for approval...");
            await approveTx.wait();
            console.log("Approval confirmed!");
            
            const newAllowance = await token.allowance(deployer.address, POOL_PROXY);
            console.log(`New allowance: ${ethers.formatUnits(newAllowance, decimals)}`);
        } else {
            console.log("Sufficient allowance exists");
        }
        
        // STEP 4: Get pool contract
        console.log("\nSTEP 4: PREPARING POOL CONTRACT");
        console.log("===============================");
        
        const pool = await ethers.getContractAt([
            {
                "inputs": [
                    {"internalType": "address", "name": "asset", "type": "address"},
                    {"internalType": "uint256", "name": "amount", "type": "uint256"},
                    {"internalType": "address", "name": "onBehalfOf", "type": "address"},
                    {"internalType": "uint16", "name": "referralCode", "type": "uint16"}
                ],
                "name": "supply",
                "outputs": [],
                "stateMutability": "nonpayable",
                "type": "function"
            },
            {
                "inputs": [{"internalType": "address", "name": "user", "type": "address"}],
                "name": "getUserAccountData",
                "outputs": [
                    {"internalType": "uint256", "name": "totalCollateralBase", "type": "uint256"},
                    {"internalType": "uint256", "name": "totalDebtBase", "type": "uint256"},
                    {"internalType": "uint256", "name": "availableBorrowsBase", "type": "uint256"},
                    {"internalType": "uint256", "name": "currentLiquidationThreshold", "type": "uint256"},
                    {"internalType": "uint256", "name": "ltv", "type": "uint256"},
                    {"internalType": "uint256", "name": "healthFactor", "type": "uint256"}
                ],
                "stateMutability": "view",
                "type": "function"
            }
        ], POOL_PROXY);
        
        console.log(`Pool contract ready: ${POOL_PROXY}`);
        
        // STEP 5: Check current account state
        console.log("\nSTEP 5: CURRENT ACCOUNT STATE");
        console.log("=============================");
        
        const accountDataBefore = await pool.getUserAccountData(deployer.address);
        console.log(`Total Collateral: $${ethers.formatUnits(accountDataBefore.totalCollateralBase, 8)}`);
        console.log(`Total Debt: $${ethers.formatUnits(accountDataBefore.totalDebtBase, 8)}`);
        console.log(`Available to Borrow: $${ethers.formatUnits(accountDataBefore.availableBorrowsBase, 8)}`);
        
        const healthFactor = Number(accountDataBefore.healthFactor);
        if (healthFactor === 0) {
            console.log(`Health Factor: ∞ (No debt)`);
        } else {
            console.log(`Health Factor: ${(healthFactor / 1e18).toFixed(3)}`);
        }
        
        // STEP 6: Execute supply
        console.log("\nSTEP 6: EXECUTING SUPPLY");
        console.log("========================");
        
        console.log(`Supplying ${AMOUNT_TO_SUPPLY} ${ASSET_TO_SUPPLY}...`);
        console.log(`Asset: ${ASSET_ADDRESS}`);
        console.log(`Amount: ${amountToSupply.toString()}`);
        console.log(`To: ${deployer.address}`);
        console.log(`Referral: 0`);
        
        const supplyTx = await pool.supply(
            ASSET_ADDRESS,
            amountToSupply,
            deployer.address,
            0
        );
        
        console.log(`Supply tx: ${supplyTx.hash}`);
        console.log("Waiting for confirmation...");
        
        const receipt = await supplyTx.wait();
        console.log(`Supply successful! Gas used: ${receipt.gasUsed.toString()}`);
        
        // STEP 7: Check results
        console.log("\nSTEP 7: CHECKING RESULTS");
        console.log("========================");
        
        // Wait for state update
        await new Promise(resolve => setTimeout(resolve, 2000));
        
        // Check new token balance
        const newBalance = await token.balanceOf(deployer.address);
        const newBalanceFormatted = ethers.formatUnits(newBalance, decimals);
        const tokensUsed = balance - newBalance;
        
        console.log(`New ${ASSET_TO_SUPPLY} balance: ${newBalanceFormatted}`);
        console.log(`Tokens used: ${ethers.formatUnits(tokensUsed, decimals)}`);
        
        // Check new account data
        const accountDataAfter = await pool.getUserAccountData(deployer.address);
        console.log("\nAfter supply:");
        console.log(`Total Collateral: $${ethers.formatUnits(accountDataAfter.totalCollateralBase, 8)}`);
        console.log(`Total Debt: $${ethers.formatUnits(accountDataAfter.totalDebtBase, 8)}`);
        console.log(`Available to Borrow: $${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
        
        const collateralIncrease = accountDataAfter.totalCollateralBase - accountDataBefore.totalCollateralBase;
        const borrowingIncrease = accountDataAfter.availableBorrowsBase - accountDataBefore.availableBorrowsBase;
        
        console.log("\nChanges:");
        console.log(`Collateral increased by: $${ethers.formatUnits(collateralIncrease, 8)}`);
        console.log(`Borrowing power increased by: $${ethers.formatUnits(borrowingIncrease, 8)}`);
        
        // STEP 8: Get aToken balance
        console.log("\nSTEP 8: CHECKING ATOKEN BALANCE");
        console.log("===============================");
        
        const poolDataProvider = await ethers.getContractAt([
            {
                "inputs": [{"internalType": "address", "name": "asset", "type": "address"}],
                "name": "getReserveTokensAddresses",
                "outputs": [
                    {"internalType": "address", "name": "aTokenAddress", "type": "address"},
                    {"internalType": "address", "name": "stableDebtTokenAddress", "type": "address"},
                    {"internalType": "address", "name": "variableDebtTokenAddress", "type": "address"}
                ],
                "stateMutability": "view",
                "type": "function"
            }
        ], POOL_DATA_PROVIDER);
        
        const reserveTokens = await poolDataProvider.getReserveTokensAddresses(ASSET_ADDRESS);
        const aTokenAddress = reserveTokens.aTokenAddress;
        console.log(`aToken address: ${aTokenAddress}`);
        
        const aToken = await ethers.getContractAt([
            {
                "inputs": [{"internalType": "address", "name": "account", "type": "address"}],
                "name": "balanceOf",
                "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
                "stateMutability": "view",
                "type": "function"
            }
        ], aTokenAddress);
        
        const aTokenBalance = await aToken.balanceOf(deployer.address);
        const aTokenBalanceFormatted = ethers.formatUnits(aTokenBalance, decimals);
        console.log(`Your a${ASSET_TO_SUPPLY} balance: ${aTokenBalanceFormatted}`);
        
        // STEP 9: Summary
        console.log("\nSUMMARY");
        console.log("=======");
        console.log(`Successfully supplied ${ethers.formatUnits(tokensUsed, decimals)} ${ASSET_TO_SUPPLY}`);
        console.log(`Received ${aTokenBalanceFormatted} a${ASSET_TO_SUPPLY} tokens`);
        console.log(`Collateral value increased by $${ethers.formatUnits(collateralIncrease, 8)}`);
        console.log(`Can now borrow up to $${ethers.formatUnits(accountDataAfter.availableBorrowsBase, 8)}`);
        
        console.log("\nNext steps:");
        console.log("1. Check balances: npx hardhat run scripts/check-balances.js --network flow_mainnet");
        console.log("2. Borrow assets: npx hardhat run scripts/borrow-from-more.js --network flow_mainnet");
        console.log("3. Withdraw supply: npx hardhat run scripts/withdraw-from-more.js --network flow_mainnet");
        
    } catch (error) {
        console.error("\nSUPPLY FAILED:");
        console.error("==============");
        console.error(error.message);
        
        if (error.message.includes("Insufficient balance")) {
            console.log("\nSOLUTION: Get more tokens or reduce the amount");
        } else if (error.message.includes("ERC20InsufficientAllowance")) {
            console.log("\nSOLUTION: Approval failed, try running again");
        } else if (error.message.includes("RESERVE_INACTIVE")) {
            console.log("\nSOLUTION: Choose a different asset");
        } else if (error.message.includes("RESERVE_FROZEN")) {
            console.log("\nSOLUTION: Asset is frozen, try later");
        }
        
        console.log("\nDEBUG:");
        console.log(`Token: ${ASSET_ADDRESS}`);
        console.log(`Pool: ${POOL_PROXY}`);
        console.log(`Amount: ${AMOUNT_TO_SUPPLY}`);
        
        throw error;
    }
}

main().catch(console.error);