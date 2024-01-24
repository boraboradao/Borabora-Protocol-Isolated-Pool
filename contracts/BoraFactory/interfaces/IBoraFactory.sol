// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBoraFactory {
    
    event CreatedPool(
        bool isOfficial,
        bytes7 customParams,
        address pool,
        address creater,
        bytes32 poolLpName,
        bytes32 poolId
    );

    event TransferedPool(bytes32 poolId, address oldOwner, address newOwner);

    event SetTargetAsset(bytes32 targetAsset, bool isAllowed);
    
    event SetOfficialPool(bytes32 poolId, bool isOfficial);

    function createPool(
        bytes7 customParams,
        address operator,
        bytes32 poolLpName,
        bytes32 poolId
    ) external returns (address pool);
}
