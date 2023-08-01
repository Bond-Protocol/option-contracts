// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockFOTERC20 is MockERC20 {
    address public feeReceiver;
    uint256 public fee;
    uint256 public constant FEE_DECIMALS = 1e5;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _feeReceiver,
        uint256 _fee
    ) MockERC20(_name, _symbol, _decimals) {
        feeReceiver = _feeReceiver;
        fee = _fee;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        balanceOf[msg.sender] -= amount;

        uint256 feeAmount = (amount * fee) / FEE_DECIMALS;

        unchecked {
            balanceOf[to] += (amount - feeAmount);
            balanceOf[feeReceiver] += feeAmount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        uint256 feeAmount = (amount * fee) / FEE_DECIMALS;

        unchecked {
            balanceOf[to] += (amount - feeAmount);
            balanceOf[feeReceiver] += feeAmount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
