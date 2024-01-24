// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct PositionCloseInfo {
    bool isProfit;
    uint256 closingTradingVolume;
    uint256 pnl;
    uint256 serviceFee;
    uint256 fundingFee;
    uint256 executorFee;
    uint256 transferOut;
    uint256 afterTotalSupply;
    uint256 afterPoolLiquidity;
    uint256 afterPoolLongShortAmount;
    uint256 latestAccumulatedPoolRebaseLong;
    uint256 latestAccumulatedPoolRebaseShort;
}

interface IBoraPoolPosition {
    
    function openPosition(
        bool isPreBill,
        bool direction,
        uint16 leverage,
        address operator,
        uint256 poolTokenAmount,
        uint256 targetPrice
    ) external returns(
        uint256 positionId,
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    function addMargin(
        address operator,
        uint256 positionId,
        uint256 addedPoolTokenAmount
    ) external returns(
        uint256 initMargin,
        uint256 extraMargin
    );

    function closePosition(
        bool isExecutor,
        uint8 closeType,
        address operator,
        uint256 positionId,
        uint256 poolTokenPrice,
        uint256 targetPrice,
        bytes32 serviceFeeData,
        bytes32 executorFeeData
    ) external returns(
        PositionCloseInfo memory info
    );

    function execPreBill(
        address positionOwner,
        uint256 positionId,
        uint256 targetPrice
    ) external returns(
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    function cancelPreBill(
        bool isClosedByExecutor,
        address operator,
        uint256 positionId
    ) external;
}
