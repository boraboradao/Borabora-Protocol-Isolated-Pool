// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;


interface IExBora {
    event SetManager(address indexed manager, bool isValid);

    event SetTransferor(address indexed transferor, bool isValid);

    event SetIsOpenTransfered(bool isOpened);
}
