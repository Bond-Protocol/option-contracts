// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBondOracle} from "src/interfaces/IBondOracle.sol";

contract MockBondOracle is IBondOracle {
    mapping(ERC20 => mapping(ERC20 => uint8)) internal _decimals;
    mapping(ERC20 => mapping(ERC20 => uint256)) internal _prices;

    constructor() {}

    function setPrice(ERC20 quoteToken_, ERC20 payoutToken_, uint256 price_) external {
        _prices[quoteToken_][payoutToken_] = price_;
    }

    function setDecimals(ERC20 quoteToken_, ERC20 payoutToken_, uint8 decimals_) external {
        _decimals[quoteToken_][payoutToken_] = decimals_;
    }

    function currentPrice(
        ERC20 quoteToken_,
        ERC20 payoutToken_
    ) external view override returns (uint256) {
        return _prices[quoteToken_][payoutToken_];
    }

    function decimals(
        ERC20 quoteToken_,
        ERC20 payoutToken_
    ) external view override returns (uint8) {
        return _decimals[quoteToken_][payoutToken_];
    }
}
