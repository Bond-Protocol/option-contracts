// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {IAllowlist} from "src/interfaces/IAllowlist.sol";
import {ITokenBalance} from "src/interfaces/ITokenBalance.sol";

/// @title  TokenAllowlist Contract
/// @notice Allowlist contract that checks if a user's balance of a token is above a threshold
/// @dev    This shouldn't be used with liquid, transferable ERC-20s because it can easily be bypassed via flash loans or other swap mechanisms
/// @dev    The intent is to use this with non-transferable tokens (e.g. vote escrow) or illiquid tokens that are not as easily manipulated, e.g. community NFTs
/// @author Bond Protocol
contract TokenAllowlist is IAllowlist, ReentrancyGuard {
    /* ========== ERRORS ========== */
    error Allowlist_InvalidParams();

    /* ========== EVENTS ========== */
    event Registered(
        address indexed contract_,
        uint256 indexed id_,
        address token_,
        uint96 threshold_
    );

    /* ========== STATE VARIABLES ========== */

    struct TokenCheck {
        ITokenBalance token;
        uint96 threshold;
    }

    mapping(address => TokenCheck) public checks;
    mapping(address => mapping(uint256 => TokenCheck)) public marketChecks;

    /* ========== CONSTRUCTOR ========== */
    constructor() {}

    /* ========== CHECK ALLOWLIST ========== */
    /// @inheritdoc IAllowlist
    function isAllowed(address user_, bytes calldata proof_) external view override returns (bool) {
        // External proof data isn't needed for this implementation

        // Get the allowlist token and balance threshold for the sender contract
        TokenCheck memory check = checks[msg.sender];

        // Return whether or not the user passes the balance threshold check
        return check.token.balanceOf(user_) >= uint256(check.threshold);
    }

    /// @inheritdoc IAllowlist
    function isAllowed(
        uint256 id_,
        address user_,
        bytes calldata proof_
    ) external view override returns (bool) {
        // External proof data isn't needed for this implementation

        // Get the allowlist token and balance threshold for the sender contract
        TokenCheck memory check = marketChecks[msg.sender][id_];

        // Return whether or not the user passes the balance threshold check
        return check.token.balanceOf(user_) >= uint256(check.threshold);
    }

    /* ========== REGISTER ALLOWLIST ========== */
    /// @inheritdoc IAllowlist
    function register(bytes calldata params_) external override nonReentrant {
        // Decode the params to get the token contract and balance threshold
        (ITokenBalance token, uint96 threshold) = abi.decode(params_, (ITokenBalance, uint96));

        // Token must be a contract
        if (address(token).code.length == 0) revert Allowlist_InvalidParams();

        // Try to get balance for token, revert if it fails
        try token.balanceOf(address(this)) returns (uint256) {} catch {
            revert Allowlist_InvalidParams();
        }

        // Set the token check parameters for the sender contract
        checks[msg.sender] = TokenCheck(token, threshold);

        // Emit an event
        emit Registered(msg.sender, 0, address(token), threshold);
    }

    /// @inheritdoc IAllowlist
    function register(uint256 id_, bytes calldata params_) external override nonReentrant {
        // Decode the params to get the token contract and balance threshold
        (ITokenBalance token, uint96 threshold) = abi.decode(params_, (ITokenBalance, uint96));

        // Token must be a contract
        if (address(token).code.length == 0) revert Allowlist_InvalidParams();

        // Try to get balance for token, revert if it fails
        try token.balanceOf(address(this)) returns (uint256) {} catch {
            revert Allowlist_InvalidParams();
        }

        // Set the token check parameters for the sender contract
        marketChecks[msg.sender][id_] = TokenCheck(token, threshold);

        // Emit an event
        emit Registered(msg.sender, id_, address(token), threshold);
    }
}
