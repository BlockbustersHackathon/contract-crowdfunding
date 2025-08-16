// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract LaunchToken is ERC20, ERC20Permit, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        address initialOwner
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        Ownable(initialOwner)
    {}

    // The functions below are overrides required by Solidity.
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}