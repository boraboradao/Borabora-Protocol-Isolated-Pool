// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBoraPoolLiquidity {
 
    function addLiquidity(
        address operator,
        uint256 poolTokenAmount
    ) external returns(
        uint256 newLPTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    function requestRemoveLiquidity(
        address operator,
        uint256 lpTokenAmount
    ) external returns(uint64 dueDate);

    function claimRemoveLiquidity(
        uint64 dueDate,
        address operator,
        bytes32 serviceFeeData
    ) external returns(
        uint256 removeLiquidityFee,
        uint256 removePoolTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    function withdraw(
        address tokenAddr,
        address to,
        uint256 amount
    ) external;
    
    function editLiquidityForEmergency(
        bool isAdd,
        address operator,
        uint256 amount
    ) external returns(
        uint256 resultAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );
}
