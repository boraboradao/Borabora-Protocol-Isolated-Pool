// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../BoraPool/interfaces/IBoraPoolLiquidity.sol";
import "../BoraFactory/interfaces/IBoraFactory.sol";
import "./interfaces/IBoraRouter.sol";
import "./BoraRouterExplore.sol";
import "./BoraRouterStructs.sol";
import "../library/Price.sol";

contract BoraRouter is UUPSUpgradeable, BoraRouterExplore, IBoraRouter{
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    mapping(address pool => bool isProhibited) public isProhibitedAddPools;

    function initialize(
        uint24 signTimestampLatency_,
        uint32 blockAmountLimit_,
        uint64 exploreThreshold_,
        uint64 minOpenAmount_,
        uint96 unexcavatedBlockExBoraAmount_,
        uint96 excavatedBlockExBoraAmount_,
        address exBora_,
        address factory_,
        bytes32 serviceFeeData_,
        bytes32 executorFeeData_
    ) public initializer {
        __Ownable_init(msg.sender);
        __storage_init(
            signTimestampLatency_,
            minOpenAmount_,
            factory_,
            serviceFeeData_,
            executorFeeData_
        );
        __explore_init(
            blockAmountLimit_,
            exploreThreshold_,
            unexcavatedBlockExBoraAmount_,
            excavatedBlockExBoraAmount_,
            exBora_
        );
    }

    function createPool(
        CreatePoolInput calldata input
    ) external onlyOpen returns (address pool) {
        
        _isValidSignature(
            CexUsage.CreatePool,
            input.signTimestamp,
            address(0),
            msg.sender,
            0,
            input.poolTokenPrice,
            0,
            input.signature
        );
        
        pool = IBoraFactory(factory).createPool(
            input.customParams,
            msg.sender,
            input.poolLpName,
            input.poolId
        );

        if (
            Price.mulE18(input.poolTokenAmount, input.poolTokenPrice)
            < 
            (uint256(minOpenAmountGlobal) * 2e14)
        ) revert("InvalidMinLiquidity");

        addLiquidity(pool, input.poolTokenAmount);
    }

    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    //                                           Position           
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    
    function openPosition(
        OpenPositionInput calldata input
    ) external onlyOpen returns(uint256){
        
        address operator = msg.sender; 

        if(input.isPreBill){
            _isValidSignature(
                CexUsage.OpenPositionPreBill,
                input.signTimestamp,
                input.pool,
                operator,
                0,
                input.poolTokenPrice,
                input.targetPrice,
                input.signature
            );
        }else {
            _isValidSignature(
                CexUsage.OpenPosition,
                input.signTimestamp,
                input.pool,
                operator,
                0,
                input.poolTokenPrice,
                input.targetPrice,
                input.signature
            );
        }
        
        if (
            Price.mulE18(input.poolTokenPrice, input.poolTokenAmount)
            <
            (minOpenAmountGlobal * 1e14)
        )
            revert("InvalidMinOpen");

        (
            uint256 positionId,
            uint256 openPrice,
            uint256 openRebase,
            uint256 afterPoolLongShortAmount,
            uint256 latestAccumulatedPoolRebaseLong,
            uint256 latestAccumulatedPoolRebaseShort
        )
            = IBoraPoolPosition(input.pool).openPosition(
                input.isPreBill,
                input.direction,
                input.leverage,
                operator,
                input.poolTokenAmount,
                input.targetPrice
            );

        bytes32 openData;
        assembly{
            openData :=
                or(
                    or(
                        or(
                            shl(0xf8, calldataload(0x24)),
                            shl(0xf0, calldataload(0x44))),
                            shl(0xe0, calldataload(0x64))),
                            caller())
        }
        // openData: Contains opening data from multiple opening inputs
        //    0x00 00 0000 0000000000000000 0000000000000000000000000000000000000000
        //      |  |  |                     |____ 20bytes positionOwner
        //      |  |  |__________________________  2bytes leverage(0)
        //      |  |_____________________________  1bytes direction      0:long 1:short
        //      |________________________________  1bytes isPreBill

        emit OpenedPosition(
            openData,
            input.pool,
            positionId,
            input.poolTokenAmount,
            input.poolTokenPrice,
            input.targetPrice,
            openPrice,
            openRebase,
            afterPoolLongShortAmount,
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        );

        return positionId;
    }

    function addMargin(
        address pool,
        uint256 positionId,
        uint256 addedPoolTokenAmount
    ) external onlyOpen {
        (uint256 initMargin, uint256 extraMargin) =
            IBoraPoolPosition(pool).addMargin(
                msg.sender,
                positionId,
                addedPoolTokenAmount
            );

        emit AddedMargin(
            pool,
            positionId,
            addedPoolTokenAmount,
            initMargin,
            extraMargin
        );
    }

    function closePosition(
        ClosePositionInput calldata input
    ) external onlyOpen {
        address operator = msg.sender;
        _isValidSignature(
            CexUsage.ClosePosition,
            input.signTimestamp,
            input.pool,
            operator,
            input.positionId,
            input.poolTokenPrice,
            input.targetPrice,
            input.signature
        );

        PositionCloseInfo memory closeInfo = 
            IBoraPoolPosition(input.pool).closePosition(
                isExecutor(operator),
                input.closeType,
                operator,
                input.positionId,
                input.poolTokenPrice,
                input.targetPrice,
                _serviceFeeData,
                _executorFeeData
            );

        // uint256 exploreThreshold256 = uint256(exploreThreshold) * 1e14;
        // uint256 remainingExBora = totalUnexcavatedExBora;
        // uint256 exBoraAmountExcavated;
        // if (
        //     closeInfo.closingTradingVolume >= exploreThreshold256
        //     && isAllowedExplorePools[input.pool]
        //     && remainingExBora > 0
        //    ) {
        //     exBoraAmountExcavated = _excavate(
        //         closeInfo.closingTradingVolume,
        //         exploreThreshold256,
        //         remainingExBora,
        //         input.positionOwner
        //     );
        //    }
      
        emit ClosedPosition(
            input.closeType,
            operator,
            _executorFeeData,
            input.pool,
            input.positionId,
            input.poolTokenPrice,
            input.targetPrice,
            0, // exBoraAmountExcavated
            closeInfo
        );
    }

    function execPreBill(
        ExecPreBillInput calldata input
    ) external {  
        address operator = msg.sender;
        require(isExecutor(operator), "Not Executor");

        (
            uint256 openPrice,
            uint256 openRebase,
            uint256 afterPoolLongShortAmount,
            uint256 latestAccumulatedPoolRebaseLong,
            uint256 latestAccumulatedPoolRebaseShort
        ) =
            IBoraPoolPosition(input.pool).execPreBill(
            input.positionOwner,
            input.positionId,
            input.targetPrice
        );

        emit ExecedPreBill(
            operator,
            input.pool,
            input.positionId,
            input.targetPrice,
            openPrice,
            openRebase,
            afterPoolLongShortAmount,
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        );
    }

    function cancelPreBill(
        address pool,
        uint256 positionId
    ) external onlyOpen {
        address operator = msg.sender;
        bool isClosedByExecutor = isExecutor(operator);

        IBoraPoolPosition(pool).cancelPreBill(
            isClosedByExecutor,
            operator,
            positionId
        );

        emit CancelPreBill(pool, positionId, isClosedByExecutor, operator);
    }

    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    //                                           Liquidity           
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    
    function addLiquidity(
        address pool,
        uint256 poolTokenAmount
    ) public onlyOpen returns(uint256){
        address operator = msg.sender;
        if (isProhibitedAddPools[pool]) revert("ProhibitAddLiquidity");

        (
            uint256 newLPTokenAmount,
            uint256 afterTotalSupply,
            uint256 afterPoolLiquidity,
            uint256 latestAccumulatedPoolRebaseLong,
            uint256 latestAccumulatedPoolRebaseShort
        ) = 
            IBoraPoolLiquidity(pool).addLiquidity(operator, poolTokenAmount);
        
        emit AddLiquidity(
            pool,
            operator,
            poolTokenAmount,
            newLPTokenAmount,
            afterTotalSupply,
            afterPoolLiquidity,
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        );
        return newLPTokenAmount;
    }

    function requestRemoveLiquidity(
        address pool,
        uint256 lpTokenAmount
    ) external onlyOpen returns(uint64 dueDate){
        address operator = msg.sender;
        dueDate = IBoraPoolLiquidity(pool).requestRemoveLiquidity(operator, lpTokenAmount);

        emit RequestRemoveLiquidity(pool, operator, lpTokenAmount, dueDate);
    }

    function claimRemoveLiquidity(
        address pool,
        uint64 dueDate
    ) external onlyOpen {
        address operator = msg.sender;
        (
            uint256 removeLiquidityFee,
            uint256 removePoolTokenAmount,
            uint256 afterTotalSupply,
            uint256 afterPoolLiquidity,
            uint256 latestAccumulatedPoolRebaseLong,
            uint256 latestAccumulatedPoolRebaseShort
        )
            = IBoraPoolLiquidity(pool).claimRemoveLiquidity(dueDate, operator, _serviceFeeData);
        
        emit ClaimRemoveLiquidity(
            pool,
            operator,
            dueDate,
            removeLiquidityFee,
            removePoolTokenAmount,
            afterTotalSupply,
            afterPoolLiquidity,
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        );
    }

    function editLiquidityForEmergency(
        address pool,
        bool isAdd,
        uint256 amount
    ) external onlyOwner {
        address operator = msg.sender;
        (
            uint256 resultAmount,
            uint256 afterTotalSupply,
            uint256 afterPoolLiquidity,
            uint256 latestAccumulatedPoolRebaseLong,
            uint256 latestAccumulatedPoolRebaseShort
        ) = 
            IBoraPoolLiquidity(pool).editLiquidityForEmergency(isAdd, operator, amount);
        
        emit EditLiquidityForEmergency(
            pool,
            isAdd,
            amount,
            resultAmount,
            afterTotalSupply,
            afterPoolLiquidity,
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        );
    }

    function poolLpTransferEvent(address from, address to, uint256 value) external {
        emit PoolLpTransferEvent(msg.sender, from, to, value);
    }
    
    // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
    
    function setProhibitAddLiquidityPools(
        address[] calldata pools,
        bool isProhibited
    ) public onlyOwner {
        for (uint256 i = 0; i < pools.length; ++i) {
            isProhibitedAddPools[pools[i]] = isProhibited;
            emit SetProhibitAddLiquidityPool(pools[i], isProhibited);
        }
    }

    function _isValidSignature(
        CexUsage cexUsage,
        uint256 signTimestamp,
        address pool,
        address operator,
        uint256 positionId,
        uint256 poolTokenPrice,
        uint256 targetPrice,
        bytes memory signature
    ) internal {
        uint256 blockTimestamp = block.timestamp * 1000;
        if (
            signTimestamp > blockTimestamp ||
            blockTimestamp - signTimestamp > signTimestampLatency * 1000
        )
            revert("InvalidSIGTimestamp");

        bytes32 signHash = keccak256(
            abi.encodePacked(
                "CexPrice",
                pool,
                operator,
                cexUsage,
                positionId,
                poolTokenPrice,
                targetPrice,
                signTimestamp
            )
        );

        if(_signatures[signHash]) revert("UsedSIG");

        address signer = signHash.toEthSignedMessageHash().recover(signature);

        require(isExecutor(signer), "Error-Sign");
        _signatures[signHash] = true;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}