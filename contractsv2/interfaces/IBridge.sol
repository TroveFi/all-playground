// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBridge {
    struct BridgeRequest {
        bytes32 id;
        uint16 srcChainId;
        uint16 dstChainId;
        address token;
        uint256 amount;
        address sender;
        address recipient;
        bytes data;
        uint256 timestamp;
        bool completed;
    }

    function bridgeToOptimalStrategy(
        uint256 amount,
        uint256 maxRiskTolerance,
        bytes calldata data
    ) external payable returns (bytes32 requestId);

    function bridgeToken(
        uint16 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external payable returns (bytes32 requestId);

    function getBridgeFee(uint16 dstChainId, uint256 amount) external view returns (uint256 fee);
    
    function isChainSupported(uint16 chainId) external view returns (bool supported);
}