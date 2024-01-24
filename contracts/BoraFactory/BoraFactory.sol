// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../BoraPool/interfaces/IBoraPoolLiquidity.sol";
import "./BoraFactoryStorage.sol";
import "./interfaces/IBoraFactory.sol";
import "../library/Price.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract BoraFactory is UUPSUpgradeable, BoraFactoryStorage, IBoraFactory {
    
    function initialize(
        address poolBeacon_,
        address dao_,
        address router_,
        bytes32 globalParams_
    ) public initializer {
        __Ownable_init(msg.sender);
        __storage_init(
            poolBeacon_,
            dao_,
            router_,
            globalParams_
        );
    }

    // poolId: poolToken address + keccak256(targetAsset) right bytes12
    //    0x0000000000000000000000000000000000000000 000000000000000000000000
    //      |                                        |____ 12 bytes targetAssetHash12
    //      |_____________________________________________ 20 bytes poolTokenAddr
    //
    // poolLpName: ERC20 poolLpToken name ,as “BTC/USD-TRX LP”
    //    0x03 03 03 4254432f5553442d545258204c50000000000000000000000000000000
    //      |  |  |  |____________________________________ 29 bytes totalString
    //      |  |  |_______________________________________  1 bytes poolTokenLen
    //      |  |__________________________________________  1 bytes targetAssetTokenBLen
    //      |_____________________________________________  1 bytes targetAssetTokenALen
    //
    // customParams: Customized configuration parameters by the creator of the pool
    //    0x0003 0002 0001 14
    //      |    |    |    |______________________________ 1 bytes marginRate(2)
    //      |    |    |___________________________________ 2 bytes maxLeverage(0)
    //      |    |________________________________________ 2 bytes slippageKRate(4)
    //      |_____________________________________________ 2 bytes imbalanceThreshold(4)

    function createPool(
        bytes7 customParams,
        address operator,
        bytes32 poolLpName,
        bytes32 poolId
    ) external onlyRouter returns (address poolAddr) {
        bool isOfficial = pools[poolId].isOfficial;
        if (pools[poolId].poolAddr != address(0)) {
            revert("ExistedPool");
        } else {
            if (isOfficial) {
                require(hasRole(EXECUTOR_ROLE, operator), "OfficialPoolDeny");
            }
        }

        bytes7 poolParams = _checkParams(customParams, poolLpName);
        _checkTargetAsset(poolId, poolLpName);

        bytes memory bytecode = _getPoolByteCode(
            poolParams,
            poolLpName,
            poolId
        );

        assembly {
            poolAddr := create2(0, add(bytecode, 0x20), mload(bytecode), poolId)

            if iszero(poolAddr) {
                mstore(0x00, ErrorOpCode)
                mstore(0x20, ErrorOpCodeOffset)
                mstore(0x40, ErrorCreate2)
                revert(0x00, 0x64)
            }
        }

        pools[poolId].poolAddr = poolAddr;
        pools[poolId].owner = operator;

        emit CreatedPool(
            isOfficial,
            poolParams,
            poolAddr,
            operator,
            poolLpName,
            poolId
        );
    }

    function transferPool(bytes32 poolId, address newOwner) external {
        address oldOwner = msg.sender;
        require(pools[poolId].owner == oldOwner, "InvalidPoolOwner");
        pools[poolId].owner = newOwner;
        
        emit TransferedPool(poolId, oldOwner, newOwner);
    }

    function getTargetAsset(    
        bytes12 targetAssetHash12
    ) public view returns (bytes32 targetAsset) {
        assembly {
            targetAsset := sload(targetAssetHash12)
        }
    }

    function getTargetAssetStr(
        bytes12 targetAssetHash12
    ) public view returns (string memory) {
        assembly {
            let targetAsset := sload(targetAssetHash12)

            let rightLen := and(targetAsset, 0xff)
            let strLen := add(byte(0xf, targetAsset), and(targetAsset, 0xff))

            let strData := or(
                or(
                    and(
                        shr(0x8, targetAsset),
                        0xffffffffffffffffffffffffffffff
                    ),
                    shl(mul(0x8, rightLen), 0x2f)
                ),
                shl(mul(0x8, add(rightLen, 0x1)), shr(0x88, targetAsset))
            )

            let str := or(
                shl(0xf8, add(0x1, strLen)),
                shl(mul(0x8, sub(0x1e, strLen)), strData)
            )

            mstore(0x00, 0x20)
            mstore(0x3f, str)
            return(0x00, 0x60)
        }
    }

    function setOfficialPools(
        bytes32[] calldata poolIds,
        bool isOfficial
    ) public onlyOwner {
        for (uint256 i; i < poolIds.length; ++i) {
            pools[poolIds[i]].isOfficial = isOfficial;
            emit SetOfficialPool(poolIds[i], isOfficial);
        }
    }

    function computePoolAddress(
        bytes7 customParams,
        bytes32 poolLpName,
        bytes32 poolId
    ) public view returns (address addr) {
        bytes7 poolParams = customParams & Filter | (bytes7(bytes2(slippageKRateGlobal)) >> 16);
        bytes memory bytecode = _getPoolByteCode(
            poolParams,
            poolLpName,
            poolId
        );
        bytes32 bytecodeHash = keccak256(bytecode);
        assembly {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), poolId)
            mstore(ptr, address())
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }

    function withdraw(
        address pool,
        address tokenAddr,
        address to,
        uint256 amount
    ) external onlyOwner {
        IBoraPoolLiquidity(pool).withdraw(tokenAddr, to, amount);
    }

    function _checkParams(
        bytes7 customParams,
        bytes32 poolLpName
    ) private view returns(
        bytes7 poolParams
    ){
        assembly {
            let globalData := sload(imbalanceThresholdGlobal.slot)

            if gt(
                and(shr(0xd0, customParams), 0xffff),
                and(globalData, 0xffff)
            ) {
                revertStr(ErrorCustomMaxLeverage)
            }

            if gt(
                and(shr(0xf0, customParams), 0xffff),
                and(shr(0x20, globalData), 0xffff)
            ) {
                revertStr(ErrorCustomImbalanceThreshold)
            }

            if gt(
                add(
                    add(byte(0, poolLpName), byte(1, poolLpName)),
                    byte(2, poolLpName)
                ),
                30
            ) {
                revertStr(ErrorPoolLpName)
            }

            poolParams :=
                or(
                    and(
                        customParams,
                        Filter
                    ),
                    shl(0xe0, and(shr(0x10, globalData), 0xffff))
                )

            function revertStr(errorMsg) {
                mstore(0x00, ErrorOpCode)
                mstore(0x20, ErrorOpCodeOffset)
                mstore(0x40, errorMsg)
                revert(0x00, 0x64)
            }
        }
    }

    function _getPoolByteCode(
        bytes7 poolParams,
        bytes32 poolLpName,
        bytes32 poolId
    ) private view returns (bytes memory bytecode) {
        bytecode = type(BeaconProxy).creationCode;

        bytes memory data = abi.encodeWithSelector(
            InitSelector,
            poolParams,
            poolLpName,
            poolId
        );
        bytecode = abi.encodePacked(bytecode, abi.encode(poolBeacon, data));
    }

    function _checkTargetAsset(bytes32 poolId, bytes32 poolLpName) private {
        assembly {
            let targetAsset := sload(shl(160, poolId))
            if iszero(targetAsset) {
                let tokenALen := byte(0, poolLpName)
                let tokenBLen := byte(1, poolLpName)

                switch iszero(tokenBLen)
                case true {
                    // default usd
                    targetAsset := or(
                        or(
                            shl(
                                0x88,
                                shr(
                                    mul(8, sub(32, tokenALen)),
                                    shl(24, poolLpName)
                                )
                            ),
                            shl(0x80, tokenALen)
                        ),
                        USDSTR
                    )
                }
                default {
                    let tokenAStr := shr(
                        mul(8, sub(32, tokenALen)),
                        shl(24, poolLpName)
                    )
                    let tokenBStr := shr(
                        mul(8, sub(32, tokenBLen)),
                        shl(add(32, mul(8, tokenALen)), poolLpName)
                    )
                    targetAsset := or(
                        or(
                            or(shl(0x88, tokenAStr), shl(0x80, tokenALen)),
                            shl(0x8, tokenBStr)
                        ),
                        tokenBLen
                    )
                }
                // targetAsset: for example string “BTC/USD”
                //    0x000000000000000000000000425443 03 000000000000000000000000555344 03
                //      |                              |  |                              |__  1 byte tokenB length
                //      |                              |  |_________________________________ 15 byte tokenB string
                //      |                              |____________________________________  1 byte tokenA length
                //      |___________________________________________________________________ 15 byte tokenA string

                mstore(0x00, targetAsset)
                sstore(shl(0xa0, keccak256(0x00, 0x20)), targetAsset)
            }
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
