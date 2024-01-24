// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./BoraFactoryStructs.sol";
import "./interfaces/IBoraFactoryStorage.sol";
import "../chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BoraFactoryStorage is
    OwnableUpgradeable, 
    AccessControlUpgradeable,
    IBoraFactoryStorage
{
    bytes4 constant ErrorOpCode = 0x08c379a0;
    bytes4 constant ErrorOpCodeOffset = 0x00000020;
    bytes4 constant InitSelector = 0xb58ff7c9;
    bytes7 constant Filter = 0xffff0000ffffff;
    uint256 constant USDSTR = 1431520259;

    // keccak256('EXECUTOR_ROLE')
    bytes32 constant EXECUTOR_ROLE = 
        0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63;
    // keccak256('EXECUTORADMIN_ROLE')
    bytes32 constant EXECUTORADMIN_ROLE = 
        0x1cd2396b9accc0bc49da7e5db4271e2b699db62256c4cc24b0b937a24a04485b;

    // I-CustomMaxLeverage
    bytes32 constant ErrorCustomMaxLeverage = 
        0x00000013492d437573746f6d4d61784c65766572616765000000000000000000;
    // I-CustomImbalanceThreshold
    bytes32 constant ErrorCustomImbalanceThreshold = 
        0x0000001a492d437573746f6d496d62616c616e63655468726573686f6c640000;
    // I-PoolLpName
    bytes32 constant ErrorPoolLpName = 
        0x0000000c492d506f6f6c4c704e616d6500000000000000000000000000000000;
    // Create2FailedDeployment
    bytes32 constant ErrorCreate2 = 
        0x00000017437265617465324661696c65644465706c6f796d656e740000000000;
    //---------------------------------------------------------------------------------------------------

    // storage slot
    //---------------------------------------------------------------------------------------------------
    uint16 public maxLeverageGlobal;
    uint16 public slippageKRateGlobal;
    uint16 public imbalanceThresholdGlobal;
    //---------------------------------------------------------------------------------------------------
    address public router;
    address public poolBeacon;
    address public daoAddr;

    mapping (bytes32 poolId => Pool) public pools;
    //---------------------------------------------------------------------------------------------------
    // targetAsset
    // example: 0x0000000000000000000000004254430300000000000000000000005553445404
    //          |---------------------------"BTC/USDC"---------------------------|
    
    // Mapping from targetAssetHash12 to targetAsset
    // targetAssets data
    // key: 0x0000000000000000000000000000000000000000 + targetAssetHash12
    // value: bytes32 targetAsset
    //---------------------------------------------------------------------------------------------------
    modifier onlyExecutor() {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "Not Executor");
        _;
    }

    modifier onlyRouter {
        require(msg.sender == router, "Not Router");
        _;
    }
    
    function __storage_init(
        address poolBeacon_,
        address dao_,
        address router_,
        bytes32 globalParams_
    ) internal {
        setPoolBeacon(poolBeacon_);
        setDAO(dao_);
        setRouter(router_);
        setPoolGlobalParams(globalParams_);
        _grantRole(EXECUTORADMIN_ROLE, msg.sender);
        _setRoleAdmin(EXECUTOR_ROLE, EXECUTORADMIN_ROLE);
    }

    function setPoolGlobalParams(
        bytes32 newGlobalParams
    ) public onlyOwner() {
        // 0x0000000000000000000000000000000000000000000000000000 0000 0000 0000
        //                                                        |    |    |
        //                 2 imbalanceThresholdGlobal(4) _________|    |    |
        //                       2 slippageKRateGlobal(4) _____________|    |
        //                        2 maxLeverageGlobal(0) ___________________|
        //
        // ------------------------------------------------------------------------
        uint256 globalParams = uint256(newGlobalParams);
        maxLeverageGlobal = uint16(globalParams);
        slippageKRateGlobal = uint16(globalParams >> 16);
        imbalanceThresholdGlobal = uint16(globalParams >> 32);
    
        emit SetPoolGlobalParams(newGlobalParams);
    }

    function setDAO(address newDAO) public onlyOwner() {
        daoAddr = newDAO;
        emit SetDAO(newDAO);
    }

    function setPoolBeacon(address newPoolBeacon) public onlyOwner() {
        poolBeacon = newPoolBeacon;
        emit SetPoolBeacon(newPoolBeacon);
    }

    function setRouter(address newRouter) public onlyOwner() {
        router = newRouter;
        emit SetRouter(router);
    }

}