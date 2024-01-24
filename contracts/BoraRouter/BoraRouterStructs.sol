// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

enum CexUsage {
    CreatePool,
    OpenPosition,
    ClosePosition,
    ExecPreBill,
    OpenPositionPreBill
}

struct CreatePoolInput {
    uint256 signTimestamp;
    bytes7 customParams;
    bytes32 poolLpName;
    bytes32 poolId;
    uint256 poolTokenAmount;
    uint256 poolTokenPrice;
    bytes signature;
}

// Input Series
struct OpenPositionInput {
    bool isPreBill;
    bool direction;  // 0:long 1:short
    uint16 leverage;
    uint256 signTimestamp;
    address pool;
    uint256 poolTokenAmount;
    uint256 poolTokenPrice;
    uint256 targetPrice;
    bytes signature;
}

struct ClosePositionInput {
    uint8 closeType;
    uint256 signTimestamp;
    address pool;
    address positionOwner;
    uint256 positionId;
    uint256 poolTokenPrice;
    uint256 targetPrice;
    bytes signature;
}

struct ExecPreBillInput {
    address pool;
    address positionOwner;
    uint256 positionId;
    uint256 targetPrice;
}
