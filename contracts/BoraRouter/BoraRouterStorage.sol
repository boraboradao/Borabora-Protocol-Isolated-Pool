// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IBoraRouterStorage.sol";

contract BoraRouterStorage is OwnableUpgradeable, IBoraRouterStorage {
    
    //-------------------------------------------------------------------------------------------------------
    // slot key: 0x0000000000000000000000000000000000000000000000000000000000000000
    bool internal _isClosedRouter;
    uint24 public signTimestampLatency;
    uint64 public minOpenAmountGlobal;  // accuracy 4
    address public factory;
    //-------------------------------------------------------------------------------------------------------
    bytes32 internal _serviceFeeData;
    // value:
    //    0x0000000000000000000000000000000000000000 000000000000 0000 0000 0000
    //      |                                                     |    |    |_____  2 serviceFeeRate(4)
    //      |                                                     |    |__________  2 serviceFeeToVaultRate(4)
    //      |                                                     |_______________  2 removeLiquidityFeeRate(4)
    //      |_____________________________________________________________________ 20 serviceFeeVault
    //
    //-------------------------------------------------------------------------------------------------------
    bytes32 internal _executorFeeData;
    // value:
    //    0x0000000000000000000000000000000000000000 00000000 00000000 00000000
    //      |                                                 |        |__________  4 closePositionGasUsage(0)
    //      |                                                 |___________________  4 execPreBillGasUsage(0)
    //      |_____________________________________________________________________ 20 executorFeeVault
    //
    //-------------------------------------------------------------------------------------------------------

    mapping(address => bool) private _executors;

    mapping(bytes32 => bool) internal _signatures;

    uint256[100] private __gap;

    modifier onlyOpen {
        if (_isClosedRouter) revert("RouterNotOpen");
        _;
    }

    function __storage_init(
        uint24 signTimestampLatency_,
        uint64 minOpenAmount_,
        address factory_,
        bytes32 serviceFeeData_,
        bytes32 executorFeeData_
    ) internal {
        setSignTimestampLatency(signTimestampLatency_);
        setMinOpenAmount(minOpenAmount_);
        setFactory(factory_);
        setServiceFeeData(serviceFeeData_);
        setExecutorFeeData(executorFeeData_);
    }
    
    function setCloseState(bool isClosed) external onlyOwner {
        _isClosedRouter = isClosed;
        emit SetCloseState(isClosed);
    }

    function setFactory(address newFactory) public onlyOwner {
        factory = newFactory;
        emit SetFactory(newFactory);
    }

    function isExecutor(address addr) public view returns(bool){
        return _executors[addr];
    }

    function setExecutors(
        address[] calldata addrs,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < addrs.length; ++i) {
            _executors[addrs[i]] = isValid;
            emit SetExecutor(addrs[i], isValid);
        }
    }
    
    function setMinOpenAmount(
        uint64 newMinOpenAmount
    ) public onlyOwner {
        minOpenAmountGlobal = newMinOpenAmount;
        emit SetMinOpenAmount(newMinOpenAmount);
    }

    function setSignTimestampLatency(
        uint24 newSignTimestampLatency
    ) public onlyOwner {
        signTimestampLatency = newSignTimestampLatency;
        emit SetSignTimestampLatency(newSignTimestampLatency);
    }

    function setExecutorFeeData(
        bytes32 newExecutorFeeData
    ) public onlyOwner {
        _executorFeeData = newExecutorFeeData;
        emit SetExecutorFeeData(newExecutorFeeData);
    }

    function setServiceFeeData(
        bytes32 newServiceFeeData
    ) public onlyOwner {
        _serviceFeeData = newServiceFeeData;
        emit SetServiceFeeData(newServiceFeeData);
    }

    function getRouterGlobalParams() public view returns(
        uint64,
        bytes32,
        bytes32
    ){
        return (
            minOpenAmountGlobal,
            _serviceFeeData,
            _executorFeeData
        );
    }
}