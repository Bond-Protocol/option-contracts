// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract TestnetERC20 is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function increaseAllowance(address spender, uint256 increaseAmount) public virtual {
        approve(spender, allowance[msg.sender][spender] + increaseAmount);
    }

    function decreaseAllowance(address spender, uint256 decreaseAmount) public virtual {
        require(
            allowance[msg.sender][spender] >= decreaseAmount,
            "ERC20: decreased allowance below zero"
        );
        approve(spender, allowance[msg.sender][spender] - decreaseAmount);
    }
}
