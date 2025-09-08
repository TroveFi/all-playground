// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "./ArbitrageTypes.sol";

contract ArbitrageDEXManager is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    address public constant PUNCH_SWAP_V2_ROUTER = 0xf45AFe28fd5519d5f8C1d4787a4D5f724C0eFa4d;
    address public constant INCREMENT_ROUTER = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address public constant QUOTER_V3 = 0x3EF68D3f7664b2805D4E88381b64868a56f88bC4;

    IPunchSwapV2Router02 public immutable punchRouter;
    IIncrementRouter public immutable incrementRouter;
    IQuoter public immutable quoter;

    mapping(address => ArbitrageTypes.DEXInfo) public dexInfo;
    address[] public activeDEXs;

    uint256 public deadlineBuffer = 300;

    event DEXUpdated(address indexed dex, string name, bool active);

    constructor() {
        punchRouter = IPunchSwapV2Router02(PUNCH_SWAP_V2_ROUTER);
        incrementRouter = IIncrementRouter(INCREMENT_ROUTER);
        quoter = IQuoter(QUOTER_V3);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _initializeDEXs();
    }

    function _initializeDEXs() internal {
        dexInfo[PUNCH_SWAP_V2_ROUTER] = ArbitrageTypes.DEXInfo({
            router: PUNCH_SWAP_V2_ROUTER,
            name: "PunchSwap V2",
            active: true,
            gasOverhead: 150000,
            feeRate: 300,
            supportsMultihop: true,
            supportsV3: false
        });
        activeDEXs.push(PUNCH_SWAP_V2_ROUTER);

        dexInfo[INCREMENT_ROUTER] = ArbitrageTypes.DEXInfo({
            router: INCREMENT_ROUTER,
            name: "Increment",
            active: true,
            gasOverhead: 180000,
            feeRate: 500,
            supportsMultihop: true,
            supportsV3: true
        });
        activeDEXs.push(INCREMENT_ROUTER);
    }

    modifier onlyStrategy() {
        require(hasRole(STRATEGY_ROLE, msg.sender), "Only strategy can call");
        _;
    }

    function swapOnPunchSwap(address tokenIn, address tokenOut, uint256 amountIn) 
        external 
        onlyStrategy 
        returns (bool success) 
    {
        if (amountIn == 0) return false;
        
        IERC20(tokenIn).safeApprove(PUNCH_SWAP_V2_ROUTER, amountIn);
        
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        
        try punchRouter.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            msg.sender,
            block.timestamp + deadlineBuffer
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function swapOnIncrement(address tokenIn, address tokenOut, uint256 amountIn) 
        external 
        onlyStrategy 
        returns (bool success) 
    {
        if (amountIn == 0) return false;
        
        IERC20(tokenIn).safeApprove(INCREMENT_ROUTER, amountIn);
        
        try incrementRouter.exactInputSingle(
            tokenIn,
            tokenOut,
            500,
            msg.sender,
            block.timestamp + deadlineBuffer,
            amountIn,
            0,
            0
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function getPrice(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        address dex
    ) external returns (uint256 amountOut) {
        if (dex == PUNCH_SWAP_V2_ROUTER) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            
            try punchRouter.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
                amountOut = amounts[1];
            } catch {
                amountOut = 0;
            }
        } else if (dex == INCREMENT_ROUTER) {
            try quoter.quoteExactInputSingle(
                tokenIn,
                tokenOut,
                500,
                amountIn,
                0
            ) returns (uint256 quote) {
                amountOut = quote;
            } catch {
                amountOut = 0;
            }
        }
    }

    function getPriceView(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn, 
        address dex
    ) external view returns (uint256 amountOut) {
        if (dex == PUNCH_SWAP_V2_ROUTER) {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            
            try punchRouter.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
                amountOut = amounts[1];
            } catch {
                amountOut = 0;
            }
        } else {
            amountOut = amountIn;
        }
    }

    function getActiveDEXs() external view returns (address[] memory) {
        return activeDEXs;
    }

    function getDEXInfo(address dex) external view returns (ArbitrageTypes.DEXInfo memory) {
        return dexInfo[dex];
    }

    function addDEX(
        address router,
        string calldata name,
        uint256 gasOverhead,
        uint256 feeRate,
        bool supportsMultihop,
        bool supportsV3
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(router != address(0), "Invalid router");
        require(!dexInfo[router].active, "DEX already added");
        
        dexInfo[router] = ArbitrageTypes.DEXInfo({
            router: router,
            name: name,
            active: true,
            gasOverhead: gasOverhead,
            feeRate: feeRate,
            supportsMultihop: supportsMultihop,
            supportsV3: supportsV3
        });
        
        activeDEXs.push(router);
        emit DEXUpdated(router, name, true);
    }

    function removeDEX(address router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(dexInfo[router].active, "DEX not active");
        
        dexInfo[router].active = false;
        
        for (uint256 i = 0; i < activeDEXs.length; i++) {
            if (activeDEXs[i] == router) {
                activeDEXs[i] = activeDEXs[activeDEXs.length - 1];
                activeDEXs.pop();
                break;
            }
        }
        
        emit DEXUpdated(router, dexInfo[router].name, false);
    }
}