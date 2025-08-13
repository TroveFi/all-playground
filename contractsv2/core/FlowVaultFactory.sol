// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./EnhancedVault.sol";

/// @title FlowVaultFactory - Enhanced Factory for Flow Mainnet
/// @notice Factory contract for creating and managing Enhanced Vault instances on Flow
contract FlowVaultFactory is Ownable {
    uint256 public vaultCounter;
    mapping(uint256 => address) public vaults;
    mapping(address => uint256) public vaultIds;
    mapping(address => bool) public isVaultCreatedByFactory;

    address public defaultManager;
    address public defaultAgent;
    uint256 public creationFee;
    address public treasury;
    
    // Enhanced factory features
    address public riskOracle;
    address public strategyRegistry;
    address public yieldAggregator;
    address public bridge;

    struct VaultParams {
        IERC20 asset;
        string name;
        string symbol;
        address manager;
        address agent;
    }

    struct VaultInfo {
        uint256 id;
        address vaultAddress;
        address asset;
        string name;
        string symbol;
        address manager;
        address agent;
        uint256 createdAt;
        address creator;
    }

    mapping(uint256 => VaultInfo) public vaultInfo;
    mapping(address => uint256[]) public vaultsByCreator;
    mapping(address => uint256[]) public vaultsByAsset;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vaultAddress,
        address indexed asset,
        string name,
        string symbol,
        address manager,
        address agent,
        address creator
    );

    event DefaultManagerUpdated(address indexed oldManager, address indexed newManager);
    event DefaultAgentUpdated(address indexed oldAgent, address indexed newAgent);
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event OraclesUpdated(address riskOracle, address strategyRegistry, address yieldAggregator);

    error InvalidAsset();
    error InvalidManager();
    error InvalidAgent();
    error InvalidTreasury();
    error EmptyName();
    error EmptySymbol();
    error InsufficientFee();
    error VaultNotFromFactory();

    constructor(
        address _defaultManager,
        address _defaultAgent,
        address _treasury,
        uint256 _creationFee,
        address _riskOracle,
        address _strategyRegistry,
        address _yieldAggregator
    ) Ownable(msg.sender) {
        defaultManager = _defaultManager;
        defaultAgent = _defaultAgent;
        treasury = _treasury;
        creationFee = _creationFee;
        riskOracle = _riskOracle;
        strategyRegistry = _strategyRegistry;
        yieldAggregator = _yieldAggregator;
    }

    function createVault(
        VaultParams calldata params
    ) external payable returns (address vaultAddress, uint256 vaultId) {
        if (address(params.asset) == address(0)) revert InvalidAsset();
        if (bytes(params.name).length == 0) revert EmptyName();
        if (bytes(params.symbol).length == 0) revert EmptySymbol();
        if (msg.value < creationFee) revert InsufficientFee();

        address manager = params.manager != address(0) ? params.manager : defaultManager;
        address agent = params.agent != address(0) ? params.agent : defaultAgent;

        if (manager == address(0)) revert InvalidManager();
        if (agent == address(0)) revert InvalidAgent();

        vaultCounter++;
        vaultId = vaultCounter;

        // Create enhanced vault with oracles
        EnhancedVault vault = new EnhancedVault(
            params.asset,
            params.name,
            params.symbol,
            manager,
            agent,
            treasury,
            riskOracle,
            strategyRegistry,
            yieldAggregator
        );

        vaultAddress = address(vault);
        vaults[vaultId] = vaultAddress;
        vaultIds[vaultAddress] = vaultId;
        isVaultCreatedByFactory[vaultAddress] = true;

        // Store vault info
        vaultInfo[vaultId] = VaultInfo({
            id: vaultId,
            vaultAddress: vaultAddress,
            asset: address(params.asset),
            name: params.name,
            symbol: params.symbol,
            manager: manager,
            agent: agent,
            createdAt: block.timestamp,
            creator: msg.sender
        });

        // Add to indexes
        vaultsByCreator[msg.sender].push(vaultId);
        vaultsByAsset[address(params.asset)].push(vaultId);

        if (creationFee > 0) {
            (bool success, ) = treasury.call{value: creationFee}("");
            require(success, "Fee transfer failed");
        }

        emit VaultCreated(vaultId, vaultAddress, address(params.asset), params.name, params.symbol, manager, agent, msg.sender);
        return (vaultAddress, vaultId);
    }

    function createVaultWithDefaults(
        IERC20 asset,
        string calldata name,
        string calldata symbol
    ) external payable returns (address vaultAddress, uint256 vaultId) {
        VaultParams memory params = VaultParams({
            asset: asset,
            name: name,
            symbol: symbol,
            manager: address(0),
            agent: address(0)
        });
        
        return createVault(params);
    }

    // View functions
    function getVaultCount() external view returns (uint256) {
        return vaultCounter;
    }

    function getAllVaults() external view returns (address[] memory vaultAddresses) {
        vaultAddresses = new address[](vaultCounter);
        for (uint256 i = 1; i <= vaultCounter; i++) {
            vaultAddresses[i - 1] = vaults[i];
        }
    }

    function getVaultsForAsset(address asset) external view returns (address[] memory vaultAddresses) {
        uint256[] memory vaultIdArray = vaultsByAsset[asset];
        vaultAddresses = new address[](vaultIdArray.length);
        
        for (uint256 i = 0; i < vaultIdArray.length; i++) {
            vaultAddresses[i] = vaults[vaultIdArray[i]];
        }
    }

    function getVaultInfo(uint256 vaultId) external view returns (VaultInfo memory) {
        return vaultInfo[vaultId];
    }

    function getVaultInfoByAddress(address vaultAddress) external view returns (VaultInfo memory) {
        uint256 vaultId = vaultIds[vaultAddress];
        if (vaultId == 0) revert VaultNotFromFactory();
        return vaultInfo[vaultId];
    }

    function isVaultCreatedByFactory(address vaultAddress) external view returns (bool) {
        return isVaultCreatedByFactory[vaultAddress];
    }

    function getVaultsByCreator(address creator) external view returns (uint256[] memory) {
        return vaultsByCreator[creator];
    }

    // Admin functions
    function setDefaultManager(address _newDefaultManager) external onlyOwner {
        if (_newDefaultManager == address(0)) revert InvalidManager();
        address oldManager = defaultManager;
        defaultManager = _newDefaultManager;
        emit DefaultManagerUpdated(oldManager, _newDefaultManager);
    }

    function setDefaultAgent(address _newDefaultAgent) external onlyOwner {
        if (_newDefaultAgent == address(0)) revert InvalidAgent();
        address oldAgent = defaultAgent;
        defaultAgent = _newDefaultAgent;
        emit DefaultAgentUpdated(oldAgent, _newDefaultAgent);
    }

    function setCreationFee(uint256 _newCreationFee) external onlyOwner {
        uint256 oldFee = creationFee;
        creationFee = _newCreationFee;
        emit CreationFeeUpdated(oldFee, _newCreationFee);
    }

    function setTreasury(address _newTreasury) external onlyOwner {
        if (_newTreasury == address(0)) revert InvalidTreasury();
        address oldTreasury = treasury;
        treasury = _newTreasury;
        emit TreasuryUpdated(oldTreasury, _newTreasury);
    }

    function updateOracles(
        address _riskOracle,
        address _strategyRegistry,
        address _yieldAggregator
    ) external onlyOwner {
        riskOracle = _riskOracle;
        strategyRegistry = _strategyRegistry;
        yieldAggregator = _yieldAggregator;
        emit OraclesUpdated(_riskOracle, _strategyRegistry, _yieldAggregator);
    }

    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = treasury.call{value: balance}("");
            require(success, "Fee withdrawal failed");
        }
    }

    receive() external payable {}
}