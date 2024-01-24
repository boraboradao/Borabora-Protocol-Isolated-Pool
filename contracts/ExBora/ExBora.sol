// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IExBora.sol";

// This token can not transfer
contract ExBora is IExBora, Ownable, ERC20 {
    mapping(address => bool) private _managers;

    modifier onlyManager() {
        require(_managers[msg.sender], "ExBora: caller is not the manager");
        _;
    }

    constructor(uint256 amount_) ERC20("Exercise Bora", "exBora") Ownable(msg.sender){
        _mint(msg.sender, amount_);
        _managers[msg.sender] = true;
    }

    function setManagers(
        address[] memory managers,
        bool isValid
    ) public onlyOwner {
        for (uint256 i = 0; i < managers.length; i++) {
            _managers[managers[i]] = isValid;
            emit SetManager(managers[i], isValid);
        }
    }

    function mint(
        address to,
        uint256 amount
    ) public onlyManager returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) public onlyManager returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function isManager(address manager) public view returns (bool) {
        return _managers[manager];
    }
}
