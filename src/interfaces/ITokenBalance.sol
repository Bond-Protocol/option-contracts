// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

/// @notice Generic interface for tokens that implement a balanceOf function (includes ERC-20 and ERC-721)
interface ITokenBalance {
    /// @notice Get the user's token balance
    function balanceOf(address user_) external view returns (uint256);
}
