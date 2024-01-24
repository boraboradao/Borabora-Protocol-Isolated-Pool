// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./BoraPoolStructs.sol";
import "src/BoraRouter/interfaces/IBoraRouterStorage.sol";

contract BoraPoolStorage is OwnableUpgradeable {
    // keccak256("rebase")
    bytes32 constant SLOTKEY001 = 0x41a1aed767a96ff20353ec646e4cfa9b88d21055bb5e0542bdd35d567d30d222;
    uint8 constant public standardPriceFeedDecimals = 8;
    uint8 constant public minLeverage = 2;
    uint16 constant public prohibitOpenRate = 20000;
    uint16 constant public slippageBRate = 0;
    uint32 constant public rebaseCoefficient = 288000;
    address immutable public standardPriceFeed;
    address immutable internal router;
    //=================================================================================================
    uint8 public poolTokenDecimals;
    uint8 public marginRate;
    uint16 public maxLeverage;
    uint16 public slippageKRate;
    address public poolToken;
    //-------------------------------------------------------------------------------------------------
    uint256 public poolLiquidity;
    uint256 public poolLongAmount;
    uint256 public poolShortAmount;
    uint256 public accumulatedPoolRebaseLong;
    uint256 public accumulatedPoolRebaseShort;

    uint256[100] private __gap;
    //-------------------------------------------------------------------------------------------------
    // slot custom and rebase data
    // key: SLOTKEY001
    // value: 0x0003 0002 0001 14 0000000000000000000000000000000000 0000000000000000
    //          |    |    |    |                                     |_________ 8 lastRebaseBlock(0)
    //          |    |    |    |_______________________________________________ 1 marginRate(2)
    //          |    |    |____________________________________________________ 2 maxLeverage(0)
    //          |    |_________________________________________________________ 2 slippageKRate(4)
    //          |______________________________________________________________ 2 imbalanceThreshold(4)
    //
    //-------------------------------------------------------------------------------------------------

    function __storage_init(
        bytes7 customParams
    ) internal {
    // poolParams_:
    //        0x0003 0002 0001 14
    //          |    |    |    |_______________________________________________ 1 marginRate(2)
    //          |    |    |____________________________________________________ 2 maxLeverage(0)
    //          |    |_________________________________________________________ 2 slippageKRate(4)
    //          |______________________________________________________________ 2 imbalanceThreshold(4)

    // ---------------------------------------- customParams ------------------------------------------
        marginRate = uint8(bytes1(customParams << 48));
        maxLeverage = uint16(bytes2(customParams << 32));
        slippageKRate = uint16(bytes2(customParams << 16));
        assembly{
            sstore(SLOTKEY001, customParams)
        }
    }

    modifier onlyRouter {
        require(msg.sender == router, "NotRouter");
        _;
    }

    function _rebase() internal returns(
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){  
        assembly{
            let rebaseData := sload(SLOTKEY001)
            let blockNumber := number()

            let lastRebaseBlock := and(rebaseData, 0xffffffffffffffff)

            let poolLiquidity_v := sload(poolLiquidity.slot)

            latestAccumulatedPoolRebaseLong := sload(accumulatedPoolRebaseLong.slot)
            latestAccumulatedPoolRebaseShort := sload(accumulatedPoolRebaseShort.slot)

            if lt(lastRebaseBlock, blockNumber){

                sstore(
                    SLOTKEY001,
                    or(
                        shl(0x40, shr(0x40, rebaseData)),
                        blockNumber
                    )
                )

                let imbalanceThreshold := shr(0xf0, rebaseData)
                let liquidityThreshold := div(mul(poolLiquidity_v, imbalanceThreshold), 10000)

                let poolLongAmount_v := sload(poolLongAmount.slot)
                let poolShortAmount_v := sload(poolShortAmount.slot)

                let longShortDiff
                switch gt(poolLongAmount_v, poolShortAmount_v)
                case 1 {
                    longShortDiff := sub(poolLongAmount_v, poolShortAmount_v)

                    if gt(longShortDiff, liquidityThreshold){
                        latestAccumulatedPoolRebaseLong := 
                            add(
                                div(
                                    div(
                                        mul(
                                            mul(
                                                sub(longShortDiff, liquidityThreshold),
                                                sub(blockNumber, lastRebaseBlock)
                                            ),
                                            0xde0b6b3a7640000   // 1e18
                                        ),
                                        rebaseCoefficient
                                    ),
                                    poolLongAmount_v
                                ),
                                latestAccumulatedPoolRebaseLong
                            )

                        sstore(accumulatedPoolRebaseLong.slot, latestAccumulatedPoolRebaseLong)

                    }
                }
                default {
                    longShortDiff := sub(poolShortAmount_v, poolLongAmount_v)

                    if gt(longShortDiff, liquidityThreshold){
                        latestAccumulatedPoolRebaseShort := 
                            add(
                                div(
                                    div(
                                        mul(
                                            mul(
                                                sub(longShortDiff, liquidityThreshold),
                                                sub(blockNumber, lastRebaseBlock)
                                            ),
                                            0xde0b6b3a7640000  // 1e18
                                        ),
                                        rebaseCoefficient
                                    ),
                                    poolShortAmount_v
                                ),
                                latestAccumulatedPoolRebaseShort
                            )

                        sstore(accumulatedPoolRebaseShort.slot, latestAccumulatedPoolRebaseShort)

                    }
                }
            }
        }
    }

    function _editPoolLiquidity(
        uint256 addAmount,
        uint256 removeAmount
    ) internal returns(
        uint256 afterPoolLiquidity
    ){
        assembly {
            afterPoolLiquidity := sub(
                add(sload(poolLiquidity.slot), addAmount),
                removeAmount
            )
            sstore(
                poolLiquidity.slot,
                afterPoolLiquidity
            )
        }
    }

    function _updatePoolLongAmount(
        uint256 addAmount,
        uint256 removeAmount
    ) internal returns(
        uint256 afterPoolLongAmount
    ){
        assembly {
            afterPoolLongAmount := sub(
                add(sload(poolLongAmount.slot), addAmount),
                removeAmount
            )
            sstore(
                poolLongAmount.slot,
                afterPoolLongAmount
            )
        }
    }

    function _updatePoolShortAmount(
        uint256 addAmount,
        uint256 removeAmount
    ) internal returns(
        uint256 afterPoolShortAmount
    ){
        assembly {
            afterPoolShortAmount := sub(
                add(sload(poolShortAmount.slot), addAmount),
                removeAmount
            )
            sstore(
                poolShortAmount.slot,
                afterPoolShortAmount
            )
        }
    }

    function getPoolGlobalParams() public view returns(
        GlobalParams memory globalParams
    ){
        (
            uint64 minOpenAmountGlobal,
            bytes32 serviceFeeData,
            bytes32 executorFeeData
        ) 
            = IBoraRouterStorage(router).getRouterGlobalParams();

        globalParams.marginRate = marginRate;
        globalParams.poolTokenDecimals = poolTokenDecimals;
        globalParams.standardPriceFeedDecimals = standardPriceFeedDecimals;
        globalParams.minLeverage = minLeverage;
        globalParams.maxLeverage = maxLeverage;
        globalParams.slippageKRate = slippageKRate;
        globalParams.slippageBRate = slippageBRate;
        globalParams.prohibitOpenRate = prohibitOpenRate;
        globalParams.rebaseCoefficient = rebaseCoefficient;
        globalParams.minOpenAmountGlobal = minOpenAmountGlobal;
        globalParams.standardPriceFeed = standardPriceFeed;
        globalParams.router = router;
        globalParams.poolToken = poolToken;
        globalParams.serviceFeeData = serviceFeeData;
        globalParams.executorFeeData = executorFeeData;
    }
    
    function getRebaseData() public view returns(
        uint16 imbalanceThreshold,
        uint64 lastRebaseBlock
    ){
        assembly {
            let rebaseData := sload(SLOTKEY001)
            imbalanceThreshold := shr(0xf0, rebaseData)
            lastRebaseBlock := and(rebaseData, 0xffffffffffffffff)
        }
    }

    function getRebaseState() public view returns(
        uint256 lastRebaseBlock,
        uint256 poolLongAmount_v,
        uint256 poolShortAmount_v,
        uint256 poolLiquidity_v,
        uint256 deviationDegree,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort,
        uint256 rebaseDelta
    ){
        assembly{
            let rebaseData := sload(SLOTKEY001)
            let blockNumber := number()

            lastRebaseBlock := and(rebaseData, 0xffffffffffffffff)

            poolLiquidity_v := sload(poolLiquidity.slot)

            latestAccumulatedPoolRebaseLong := sload(accumulatedPoolRebaseLong.slot)
            latestAccumulatedPoolRebaseShort := sload(accumulatedPoolRebaseShort.slot)

            if lt(lastRebaseBlock, blockNumber){
                let imbalanceThreshold := shr(0xf0, rebaseData)
                let liquidityThreshold := div(mul(poolLiquidity_v, imbalanceThreshold), 10000)

                poolLongAmount_v := sload(poolLongAmount.slot)
                poolShortAmount_v := sload(poolShortAmount.slot)

                let longShortDiff
                switch gt(poolLongAmount_v, poolShortAmount_v)
                case 1 {
                    longShortDiff := sub(poolLongAmount_v, poolShortAmount_v)

                    deviationDegree := div(mul(longShortDiff, 0xde0b6b3a7640000), poolLiquidity_v)

                    if gt(longShortDiff, liquidityThreshold){
                        rebaseDelta := 
                            div(
                                div(
                                    mul(
                                        mul(
                                            sub(longShortDiff, liquidityThreshold),
                                            sub(blockNumber, lastRebaseBlock)
                                        ),
                                        0xde0b6b3a7640000   // 1e18
                                    ),
                                    rebaseCoefficient
                                ),
                                poolLongAmount_v
                            )
                        latestAccumulatedPoolRebaseLong := 
                            add(
                                rebaseDelta,
                                latestAccumulatedPoolRebaseLong
                            )
                        
                    }
                }
                default {
                    longShortDiff := sub(poolShortAmount_v, poolLongAmount_v)

                    deviationDegree := div(mul(longShortDiff, 0xde0b6b3a7640000), poolLiquidity_v)

                    if gt(longShortDiff, liquidityThreshold){
                        rebaseDelta := 
                            div(
                                div(
                                    mul(
                                        mul(
                                            sub(longShortDiff, liquidityThreshold),
                                            sub(blockNumber, lastRebaseBlock)
                                        ),
                                        0xde0b6b3a7640000  // 1e18
                                    ),
                                    rebaseCoefficient
                                ),
                                poolShortAmount_v
                                )
                        latestAccumulatedPoolRebaseShort := 
                            add(
                                rebaseDelta,
                                latestAccumulatedPoolRebaseShort
                            )
                    }
                }
            }
        }
    }
}
