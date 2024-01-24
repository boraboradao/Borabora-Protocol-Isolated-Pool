// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IBoraPoolLiquidity.sol";
import "./BoraPoolStorage.sol";
import "../library/Price.sol";

contract BoraPoolLiquidity is
    ERC20Upgradeable,
    BoraPoolStorage,
    IBoraPoolLiquidity
{
    using SafeERC20 for IERC20;

    // from the router: poolLpTransferEvent(address,address,uint256)
    bytes4 private constant SELECTOR1 = 0x82e12e12;
    uint public constant MINIMUM_LIQUIDITY = 1e18;

    mapping(address => mapping(uint64 => uint256)) public liquidityRemoveAmounts;

    uint256[100] private __gap;

    function __poolLiquidity_init(
        bytes32 poolLpName_,
        bytes32 poolId_
    ) internal {
        address poolToken_ = address(bytes20(poolId_));
        poolToken = poolToken_;
        poolTokenDecimals = ERC20Upgradeable(poolToken_).decimals();

        string memory poolLpName;
        assembly{
            let strLen
            let tokenBLen := byte(1, poolLpName_)
            switch iszero(tokenBLen)
            case true {
                strLen := add(add(byte(0, poolLpName_), byte(2, poolLpName_)), 0x4)
            }
            default {
                strLen := add(add(add(byte(0, poolLpName_), tokenBLen), byte(2, poolLpName_)), 0x5)
            }

            poolLpName_ := or(shl(0xf8, strLen), shr(0x8, shl(0x18, poolLpName_)))
            mstore(add(poolLpName, 0x1f), poolLpName_)
        }

        __ERC20_init(poolLpName, poolLpName);

        _mint(0x000000000000000000000000000000000000dEaD, MINIMUM_LIQUIDITY);
        _editPoolLiquidity(MINIMUM_LIQUIDITY, 0);
    }

    
    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        bytes memory data = abi.encodePacked(SELECTOR1, abi.encode(owner, to, value));
        router.call{gas:8000}(data);

        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        bytes memory data = abi.encodePacked(SELECTOR1, abi.encode(from, to, value));
        router.call{gas:8000}(data);
       
        return true;
    }

    function addLiquidity(
        address operator,
        uint256 poolTokenAmount
    )external onlyRouter returns(
        uint256 newLPTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){  
        (
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        ) 
            = _rebase();

        uint256 curTotalSupply = totalSupply();

        newLPTokenAmount = Price.lpTokenByPoolToken(
            curTotalSupply,
            poolLiquidity,
            poolTokenAmount
        );

        _chargePoolToken(operator, poolTokenAmount);
        
        _mint(operator, newLPTokenAmount);
        afterTotalSupply = curTotalSupply + newLPTokenAmount;

        afterPoolLiquidity = _editPoolLiquidity(poolTokenAmount, 0);
    }

    function editLiquidityForEmergency(
        bool isAdd,
        address operator,
        uint256 amount
    ) external onlyRouter returns(
        uint256 resultAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){  
        (
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        ) 
            = _rebase();

        uint256 curTotalSupply = totalSupply();

        if (isAdd) {
            _chargePoolToken(operator, amount);
            resultAmount = Price.lpTokenByPoolToken(
                curTotalSupply,
                poolLiquidity,
                amount
            );
            _mint(operator, resultAmount);
            afterTotalSupply = curTotalSupply + resultAmount;
            afterPoolLiquidity = _editPoolLiquidity(amount, 0);
        } else {
            _burn(operator, amount);
            resultAmount = Price.poolTokenByLPToken(
                curTotalSupply,
                poolLiquidity,
                amount
            );
            
            _sendPoolToken(operator, resultAmount);
            afterTotalSupply = curTotalSupply - amount;
            afterPoolLiquidity = _editPoolLiquidity(0, resultAmount);
        }
    }

    function requestRemoveLiquidity(
        address operator,
        uint256 lpTokenAmount
    ) external onlyRouter returns(uint64 dueDate){

        dueDate = uint64(block.timestamp / 1 days) + 3;
        
        _transfer(operator, address(this), lpTokenAmount);
        bytes memory data = abi.encodePacked(SELECTOR1, abi.encode(operator, address(this), lpTokenAmount));
        router.call{gas:8000}(data);

        liquidityRemoveAmounts[operator][dueDate] += lpTokenAmount;
    }

    function claimRemoveLiquidity(
        uint64 dueDate,
        address operator,
        bytes32 serviceFeeData
    ) external onlyRouter returns(
        uint256 removeLiquidityFee,
        uint256 removePoolTokenAmount,
        uint256 afterTotalSupply,
        uint256 afterPoolLiquidity,
        uint256 latestAccumulatedPoolRebaseLong,
        uint256 latestAccumulatedPoolRebaseShort
    ){  
        (
            latestAccumulatedPoolRebaseLong,
            latestAccumulatedPoolRebaseShort
        ) 
            = _rebase();
        
        uint64 nowDate = uint64(block.timestamp / 1 days);
        
        if(nowDate < dueDate) revert("Unexpired");

        uint256 removeLpTokenAmount = liquidityRemoveAmounts[operator][dueDate];

        if(removeLpTokenAmount == 0) revert("NotRequestRemoveLiquidity");

        uint256 curTotalSupply = totalSupply();
        uint256 culPoolTokenAmount = Price.poolTokenByLPToken(
            curTotalSupply,
            poolLiquidity,
            removeLpTokenAmount
        );
        removeLiquidityFee = Price.mulE4(
                culPoolTokenAmount,
                uint16(uint256(serviceFeeData) >> 32)
        );
        removePoolTokenAmount = culPoolTokenAmount - removeLiquidityFee;

        _burn(address(this), removeLpTokenAmount);
        afterTotalSupply = curTotalSupply - removeLpTokenAmount;

        delete liquidityRemoveAmounts[operator][dueDate];
        _sendPoolToken(operator, removePoolTokenAmount);
        _sendPoolToken(address(bytes20(serviceFeeData)), removeLiquidityFee);
        afterPoolLiquidity = _editPoolLiquidity(0, culPoolTokenAmount);
    }

    function _sendPoolToken(address to, uint256 amount) internal {
        uint256 sendAmount = Price.convertDecimal(
            amount,
            18,
            poolTokenDecimals
        );

        IERC20(poolToken).safeTransfer(to, sendAmount);
    }

    function withdraw(
        address tokenAddr,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (tokenAddr == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(tokenAddr).safeTransfer(to, amount);
        }
    }
    
    function _chargePoolToken(address from, uint256 amount) internal {
        address poolToken_stack = poolToken;
        uint256 balanceBefore = IERC20(poolToken_stack).balanceOf(address(this));

        uint256 chargeAmount = Price.convertDecimal(
            amount,
            18,
            poolTokenDecimals
        );

        IERC20(poolToken_stack).safeTransferFrom(from, address(this), chargeAmount);

        if (IERC20(poolToken_stack).balanceOf(address(this)) < (balanceBefore + chargeAmount))
            revert("FailedChargePoolToken");
    }

}
