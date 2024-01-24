// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBoraFactoryStorage {

    event SetPoolGlobalParams(
        bytes32 newGlobalParams
    );

    event SetDAO(address newDAO);

    event SetRouter(address router);

    event SetPoolBeacon(address newPoolBeacon);
}