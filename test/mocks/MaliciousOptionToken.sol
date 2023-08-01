// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MaliciousOptionToken is ERC20 {
    ERC20 public payout;
    ERC20 public quote;
    uint48 public eligible;
    uint48 public expiry;
    address public receiver;
    bool public call;
    address public teller;
    uint256 public strikePrice;

    constructor(
        ERC20 payout_,
        ERC20 quote_,
        uint48 eligible_,
        uint48 expiry_,
        address receiver_,
        bool call_,
        address teller_,
        uint256 strikePrice_
    ) ERC20("Malicious Option Token", "MOT", payout_.decimals()) {
        payout = payout_;
        quote = quote_;
        eligible = eligible_;
        expiry = expiry_;
        receiver = receiver_;
        call = call_;
        teller = teller_;
        strikePrice = strikePrice_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function getOptionParameters()
        external
        view
        returns (uint8, address, address, uint48, uint48, address, bool, uint256)
    {
        return (
            payout.decimals(),
            address(payout),
            address(quote),
            eligible,
            expiry,
            receiver,
            call,
            strikePrice
        );
    }
}
