// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

enum State {
    Empty,
    PreBill,
    Opened,
    Closed
}

struct Position {
    uint8 state;
    bool isPreBill;
    bool direction;   // 0:long 1:short
    uint16 leverage;
    address owner;
    uint256 openPrice;
    uint256 initMargin;
    uint256 extraMargin;
    uint256 openRebase;
}

struct GlobalParams {
    uint8 marginRate;
    uint8 poolTokenDecimals;
    uint8 standardPriceFeedDecimals;
    uint8 minLeverage;
    uint16 maxLeverage;
    uint16 slippageKRate;
    uint16 slippageBRate;
    uint16 prohibitOpenRate;
    uint32 rebaseCoefficient;
    uint64 minOpenAmountGlobal;
    address standardPriceFeed;
    address router;
    address poolToken;
    bytes32 serviceFeeData;
    bytes32 executorFeeData;
}