// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "./interfaces/IBoraPoolPosition.sol";
import "./BoraPoolLiquidity.sol";

contract BoraPoolPosition is BoraPoolLiquidity, IBoraPoolPosition{
    using BasicMaths for uint256;
    using BasicMaths for bool;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    uint256 private _positionIdCounter;

    mapping(uint256 => Position) private _positions;

    uint256[100] private __gap;

    function openPosition(
        bool isPreBill,
        bool direction,
        uint16 leverage,
        address operator,
        uint256 poolTokenAmount,
        uint256 targetPrice
    ) external onlyRouter returns(
        uint256 positionId,
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){  
        if (leverage < minLeverage || leverage > maxLeverage)
            revert("InvalidLeverage");

        _chargePoolToken(operator, poolTokenAmount);
        
        _positionIdCounter++;
        positionId = _positionIdCounter;

        _positions[positionId].direction = direction;
        _positions[positionId].leverage = leverage;
        _positions[positionId].owner = operator;
        _positions[positionId].initMargin = poolTokenAmount;

        if (isPreBill) {
            _positions[positionId].state = uint8(State.PreBill);
            _positions[positionId].isPreBill = true;
        }else{
            (
                latestAccumulatedPoolRebaseLong,
                latestAccumulatedPoolRebaseShort
            ) 
                = _rebase();

            (openPrice, openRebase, afterPoolLongShortAmount) = _calculate(
                direction,
                leverage,
                poolTokenAmount,
                targetPrice
            );

            _positions[positionId].openRebase = openRebase;
            _positions[positionId].openPrice = openPrice;
            _positions[positionId].state = uint8(State.Opened);
        }
    }

    function addMargin(
        address operator,
        uint256 positionId,
        uint256 addedPoolTokenAmount
    ) external onlyRouter returns(
        uint256 initMargin,
        uint256 extraMargin
    ){  
        require(_positions[positionId].state == uint8(State.Opened), "PositionNotOpened");

        require(operator == _positions[positionId].owner, "Not PositionOwner");
        
        _chargePoolToken(operator, addedPoolTokenAmount);

        extraMargin = _positions[positionId].extraMargin + addedPoolTokenAmount;
        _positions[positionId].extraMargin = extraMargin;

        initMargin = _positions[positionId].initMargin;
    }

    function closePosition(
        bool isExecutor,
        uint8 closeType,
        address operator,
        uint256 positionId,
        uint256 poolTokenPrice,
        uint256 targetPrice,
        bytes32 serviceFeeData,
        bytes32 executorFeeData
    ) external onlyRouter returns(
        PositionCloseInfo memory info
    ){
        Position memory position = _positions[positionId];

        require(position.state == uint8(State.Opened), "PositionNotOpened");
        
        if(operator != position.owner && !isExecutor)
            revert("Not OwnerOrExecutor");
        
        (
            info.latestAccumulatedPoolRebaseLong,
            info.latestAccumulatedPoolRebaseShort
        )   
            = _rebase();

        uint256 positionAmount = position.initMargin * position.leverage;
        
        info.closingTradingVolume = Price.mulE18(poolTokenPrice, positionAmount);

        info.pnl = positionAmount * (targetPrice.diff(position.openPrice)) / position.openPrice;
        
        info.serviceFee = Price.mulE4(
            positionAmount,
            uint16(uint256(serviceFeeData))
        );

        uint256 serviceFeeToVault = Price.mulE4(
            info.serviceFee,
            uint16(uint256(serviceFeeData) >> 16)
        );
        _sendPoolToken(address(bytes20(serviceFeeData)), serviceFeeToVault);

        if (position.direction) {
            info.fundingFee = Price.calFundingFee(
                positionAmount,
                (accumulatedPoolRebaseShort - position.openRebase)
            );
            info.afterPoolLongShortAmount = _updatePoolShortAmount(0, positionAmount);
        } else {
            info.fundingFee = Price.calFundingFee(
                positionAmount,
                (accumulatedPoolRebaseLong - position.openRebase)
            );
            info.afterPoolLongShortAmount = _updatePoolLongAmount(0, positionAmount);
        }

        if (position.isPreBill && isExecutor) {
            info.executorFee = _chargeExecutorFee(
                uint32(uint256(executorFeeData)),
                poolTokenPrice
            ) * 2;
        } else if (!position.isPreBill && !isExecutor) {
             
        } else {
            info.executorFee = _chargeExecutorFee(
                uint32(uint256(executorFeeData)),
                poolTokenPrice
            );
        }

        info.isProfit = (targetPrice < position.openPrice) == position.direction;
        uint256 totalMargin = position.initMargin + position.extraMargin;

        // Adjusting executor fees
        if(info.executorFee > 0){
            // priority =>   1:serviceFee   2:lp income   3:executorFee
            uint256 remainingMargin = (totalMargin - info.serviceFee).sub2Zero(info.fundingFee);
            if(!info.isProfit) remainingMargin = remainingMargin.sub2Zero(info.pnl);
            if(remainingMargin < info.executorFee) info.executorFee = remainingMargin;

            if(info.executorFee > 0){
                _sendPoolToken(address(bytes20(executorFeeData)), info.executorFee);
            }
        }

        if(closeType != 3){

            info.transferOut = info.isProfit
                .addOrSub2Zero(totalMargin, info.pnl)
                .sub2Zero(info.fundingFee)
                .sub2Zero(info.serviceFee)
                .sub2Zero(info.executorFee);

            uint256 necessaryFee = serviceFeeToVault + info.executorFee + MINIMUM_LIQUIDITY;
            if (info.transferOut + necessaryFee > (poolLiquidity + totalMargin)) {
                info.transferOut = poolLiquidity + totalMargin - necessaryFee;
            }

            if (info.transferOut > 0) {
                _sendPoolToken(position.owner, info.transferOut);
            }
        }

        info.afterTotalSupply = totalSupply();

        info.afterPoolLiquidity = _editPoolLiquidity(
            totalMargin,
            info.transferOut + serviceFeeToVault + info.executorFee
        );
        
        _positions[positionId].state = uint8(State.Closed);
    }

    function execPreBill(
        address positionOwner,
        uint256 positionId,
        uint256 targetPrice
    ) external onlyRouter returns(
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){
        Position memory position = _positions[positionId];

        require(position.state == uint8(State.PreBill), "PositionNotPreBill");
        require(position.owner == positionOwner, "PositionOwnerMismatch");

        (
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        ) 
            = _rebase();

        (openPrice, openRebase, afterPoolLongShortAmount) = _calculate(
            position.direction,
            position.leverage,
            position.initMargin,
            targetPrice
        );

        _positions[positionId].openPrice = openPrice;
        _positions[positionId].openRebase = openRebase;
        _positions[positionId].state = uint8(State.Opened);

    }

    function cancelPreBill(
        bool isClosedByExecutor,
        address operator,
        uint256 positionId
    ) public onlyRouter {
        Position memory position = _positions[positionId];

        require(position.state == uint8(State.PreBill), "PositionNotPreBill");
   
        if(operator != position.owner && !isClosedByExecutor)
            revert("NotPositionOwnerOrExecutor");

        _sendPoolToken(position.owner, position.initMargin);

        _positions[positionId].state = uint8(State.Closed);
    }

    function getPosition(
        uint256 positionId
    ) external view returns (Position memory) {
        return _positions[positionId];
    }

    function _calculate(
        bool direction,
        uint16 leverage,
        uint256 poolTokenAmount,
        uint256 targetPrice
    ) private returns (
        uint256 openPrice,
        uint256 openRebase,
        uint256 afterPoolLongShortAmount
    ) {
        uint256 positionAmount = poolTokenAmount * leverage;
        if(positionAmount > poolLiquidity) revert("Illiquidity");

        uint256 afterPoolLongShortDiff;
        uint256 slippageRate;

        if (direction) {
            if ((poolShortAmount + positionAmount) < poolLongAmount) {
                afterPoolLongShortDiff = poolLongAmount - poolShortAmount - positionAmount;
            } else {
                afterPoolLongShortDiff = poolShortAmount + positionAmount - poolLongAmount;
                slippageRate = afterPoolLongShortDiff * slippageKRate / (poolLiquidity - MINIMUM_LIQUIDITY);
            }

            if(
                afterPoolLongShortDiff > Price.mulE4(poolLiquidity - MINIMUM_LIQUIDITY, prohibitOpenRate)
            )
                revert("InvalidNackedPosition");

            openPrice = targetPrice - Price.mulE4(targetPrice, slippageRate + slippageBRate);
            
            afterPoolLongShortAmount = _updatePoolShortAmount(positionAmount, 0);
            openRebase = accumulatedPoolRebaseShort;

        } else {
            if (poolShortAmount < (poolLongAmount + positionAmount)) {
                afterPoolLongShortDiff = poolLongAmount + positionAmount - poolShortAmount;
                slippageRate = afterPoolLongShortDiff * slippageKRate / (poolLiquidity - MINIMUM_LIQUIDITY);
            } else {
                afterPoolLongShortDiff = poolShortAmount - poolLongAmount - positionAmount;
            }
          
            if(
                afterPoolLongShortDiff > Price.mulE4(poolLiquidity - MINIMUM_LIQUIDITY, prohibitOpenRate)
            )
                revert("InvalidNackedPosition");
                
            openPrice = targetPrice + Price.mulE4(targetPrice, slippageRate + slippageBRate);
            
            afterPoolLongShortAmount = _updatePoolLongAmount(positionAmount, 0);
            openRebase = accumulatedPoolRebaseLong;

        }
    }

    function _chargeExecutorFee(
        uint256 usedGasAmount,
        uint256 poolTokenPrice
    ) internal view returns (uint256 finalExecutorFeeInPoolToken) {
        // Step 1: Gas mainCrypto/poolToken price
        uint256 standardPrice = uint256(
            AggregatorV2V3Interface(standardPriceFeed).latestAnswer()
        );
        standardPrice = Price.convertDecimal(standardPrice, standardPriceFeedDecimals, 18);

        // Step 2: Calculate executor fee in gas amount and pool token
        uint256 finalExecutorFeeInGasAmount = usedGasAmount * tx.gasprice; // 要求精度18

        finalExecutorFeeInPoolToken = standardPrice * finalExecutorFeeInGasAmount / poolTokenPrice;
    }


}


