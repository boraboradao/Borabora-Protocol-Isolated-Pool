// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBoraRouterStorage {

    event SetCloseState(bool isClosed);

    event SetSignTimestampLatency(uint24 newSignTimestampLatency);
    
    event SetMinOpenAmount(uint64 newMinOpenAmount);

    event SetExecutor(address, bool);

    event SetFactory(address newFactory);
    
    event SetExecutorFeeData(bytes32 newExecutorFeeData);

    event SetServiceFeeData(bytes32 newServiceFeeData);

    function getRouterGlobalParams() external view returns(
        uint64,
        bytes32,
        bytes32
    );
}
