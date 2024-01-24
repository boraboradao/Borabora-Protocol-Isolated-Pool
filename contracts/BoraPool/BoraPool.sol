// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./BoraPoolPosition.sol";

contract BoraPool is BoraPoolPosition {
    using SafeERC20 for IERC20;

    constructor(
        address standardPriceFeed_,
        address router_
    ) {
        standardPriceFeed = standardPriceFeed_;
        router = router_;
    }

    function initialize(
        bytes7 customParams_,
        bytes32 poolLpName_,
        bytes32 poolId_
    ) public initializer {
        __Ownable_init(msg.sender);
        __storage_init(customParams_);
        __poolLiquidity_init(poolLpName_, poolId_);
    }
}
