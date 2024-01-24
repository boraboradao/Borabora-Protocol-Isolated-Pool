// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../BoraPool/interfaces/IBoraPoolPosition.sol";

interface IBoraRouter {

    event OpenedPosition(
        bytes32 openData,
        address pool,
        uint256 positionId,
        uint256 poolTokenAmount,
        uint256 poolTokenPrice,
        uint256 targetPrice,
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    event AddedMargin(
        address pool,
        uint256 positionId,
        uint256 addedPoolTokenAmount,
        uint256 initMargin,
        uint256 extraMargin
    );

    event ClosedPosition(
        uint8 closeType,
        address operator,
        bytes32 executorFeeData,
        address pool,
        uint256 positionId,
        uint256 poolTokenPrice,
        uint256 targetPrice,
        uint256 exBoraAmountExcavated,
        PositionCloseInfo closeInfo
    );

    event ExecedPreBill(
        address operator,
        address pool,
        uint256 positionId,
        uint256 targetPrice,
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    event CancelPreBill(
        address pool,
        uint256 positionId,
        bool isClosedByExecutor,
        address operator
    );

    event AddLiquidity(
        address pool,
        address operator,
        uint256 poolTokenAmount,
        uint256 newLPTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    event RequestRemoveLiquidity(
        address pool,
        address operator,
        uint256 lpTokenAmount,
        uint64 dueDate
    );

    event ClaimRemoveLiquidity(
        address pool,
        address operator,
        uint64 dueDate,
        uint256 removeLiquidityFee,
        uint256 removePoolTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    event EditLiquidityForEmergency(
        address pool,
        bool isAdd,
        uint256 amount,
        uint256 resultAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    );

    event SetProhibitAddLiquidityPool(address pool, bool isProhibited);

    event PoolLpTransferEvent(address caller, address from, address to, uint256 value);
}
