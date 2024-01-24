// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBoraRouterExplore {

    event Excavated(
        address owner,
        uint256 blockNumberExcavated,
        uint256 nowBlockNumber,
        uint256 excavatedExBoraAmount
    );

    event SetTotalUnexcavatedExBora(
        uint64 latestExcavatedBlockNumber,
        uint256 newTotalUnexcavatedExBora
    );

    event SetExcavateExboraParams(
        uint32 newBlockAmountLimit,
        uint96 newUnexcavatedBlockExBoraAmount,
        uint96 newExcavatedBlockExBoraAmount
    );

    event SetExploreThreshold(uint64 newExploreThreshold);

    event SetExBora(address newExBora);

    event SetAllowPool(address pool, bool isAllowed);
}
