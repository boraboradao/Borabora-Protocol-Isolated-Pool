// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./BoraRouterStorage.sol";
import "./interfaces/IBoraRouterExplore.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BoraRouterExplore is BoraRouterStorage, IBoraRouterExplore {
    
    uint32 public blockAmountLimit;
    uint64 public exploreThreshold;     // accuracy 4
    address public exBora;
    
    uint64 public latestExcavatedBlockNumber;
    uint96 public unexcavatedBlockExBoraAmount;
    uint96 public excavatedBlockExBoraAmount;
    
    uint256 public totalUnexcavatedExBora;

    mapping(address pool => bool isAllowed) public isAllowedExplorePools;

    uint256[100] private __gap;
    
    function __explore_init(
        uint32 blockAmountLimit_,
        uint64 exploreThreshold_,
        uint96 unexcavatedBlockExBoraAmount_,
        uint96 excavatedBlockExBoraAmount_,
        address exBora_
    ) internal {
        setExcavateExboraParams(
            blockAmountLimit_,
            unexcavatedBlockExBoraAmount_,
            excavatedBlockExBoraAmount_
        );
        setExploreThreshold(exploreThreshold_);
        setExBora(exBora_);
    }

    function _excavate(
        uint256 closingTradingVolume,
        uint256 exploreThreshold256,
        uint256 remainingExBora,
        address owner
    ) internal returns (uint256 excavatedExBoraAmount) {
        
        // step 1: get block number
        uint256 nowBlockNumber = block.number;
        uint256 blockNumberExcavated = latestExcavatedBlockNumber;

        // step 2: check unexcavated block amount
        if (nowBlockNumber > blockNumberExcavated) {
            excavatedExBoraAmount = excavatedBlockExBoraAmount;
            uint256 blockAmount = nowBlockNumber - blockNumberExcavated;
            uint256 blockLimit = blockAmountLimit;

            if (blockAmount > blockLimit) {
                excavatedExBoraAmount +=
                    blockLimit *
                    unexcavatedBlockExBoraAmount *
                    closingTradingVolume / exploreThreshold256;
            } else if (blockAmount > 1) {
                excavatedExBoraAmount +=
                    unexcavatedBlockExBoraAmount *
                    (blockAmount - 1) *
                    closingTradingVolume / exploreThreshold256;
            }

            if (excavatedExBoraAmount > remainingExBora) {
                excavatedExBoraAmount = remainingExBora;
            }

            latestExcavatedBlockNumber = uint64(nowBlockNumber);
            totalUnexcavatedExBora -= excavatedExBoraAmount;

            SafeERC20.safeTransfer(
                IERC20(exBora),
                owner,
                excavatedExBoraAmount
            );

            emit Excavated(
                owner,
                blockNumberExcavated,
                nowBlockNumber,
                excavatedExBoraAmount
            );
            return excavatedExBoraAmount;
        }
    }

    function setTotalUnexcavatedExBora(
        uint256 newTotalUnexcavatedExBora
    ) public onlyOwner {
        require(
            IERC20(exBora).balanceOf(address(this)) >= newTotalUnexcavatedExBora,
            "BoraRouter: Insufficient Balance"
        );
        totalUnexcavatedExBora = newTotalUnexcavatedExBora;
        latestExcavatedBlockNumber = uint64(block.number);
        
        emit SetTotalUnexcavatedExBora(
            latestExcavatedBlockNumber,
            newTotalUnexcavatedExBora
        );
    }

    function setExcavateExboraParams(
        uint32 newBlockAmountLimit,
        uint96 newUnexcavatedBlockExBoraAmount,
        uint96 newExcavatedBlockExBoraAmount
    ) public onlyOwner {
        unexcavatedBlockExBoraAmount = newUnexcavatedBlockExBoraAmount;
        excavatedBlockExBoraAmount = newExcavatedBlockExBoraAmount;
        blockAmountLimit = newBlockAmountLimit;
        emit SetExcavateExboraParams(
            newBlockAmountLimit,
            newUnexcavatedBlockExBoraAmount,
            newExcavatedBlockExBoraAmount
        );
    }

    function setExploreThreshold(uint64 newExploreThreshold) public onlyOwner {
        exploreThreshold = newExploreThreshold;
        emit SetExploreThreshold(newExploreThreshold);
    }


    function setExBora(address newExBora) public onlyOwner {
        exBora = newExBora;
        emit SetExBora(newExBora);
    }

    function setAllowPools(
        address[] calldata pools,
        bool isAllowed
    ) public onlyOwner {
        for (uint256 i = 0; i < pools.length; ++i) {
            isAllowedExplorePools[pools[i]] = isAllowed;
            emit SetAllowPool(pools[i], isAllowed);
        }
    }


}