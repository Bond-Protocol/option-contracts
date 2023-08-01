// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {RolesAuthority, Authority} from "solmate/auth/authorities/RolesAuthority.sol";
import {MockFOTERC20} from "test/mocks/MockFOTERC20.sol";
import {MaliciousOptionToken} from "test/mocks/MaliciousOptionToken.sol";
import {MaliciousDecimalToken} from "test/mocks/MaliciousDecimalToken.sol";

import {FixedStrikeOptionTeller, FixedStrikeOptionToken, FullMath} from "src/fixed-strike/FixedStrikeOptionTeller.sol";

contract FixedStrikeOptionTest is Test {
    using FullMath for uint256;

    address public guardian;
    address public alice;
    address public bob;
    address public carol;

    RolesAuthority public auth;
    FixedStrikeOptionTeller public teller;
    MockERC20 public abc;
    MockERC20 public def;
    MockERC20 public ghi;
    MockERC20 public jklmno;

    function setUp() public {
        vm.warp((52 * 365 + (52 - 2) / 4) * 24 * 60 * 60 + 12 hours); // Set timestamp at exactly Jan 1, 2022 00:00:00 UTC (52 years since Unix epoch)

        // Setup users
        guardian = address(uint160(uint256(keccak256("guardian"))));
        alice = address(uint160(uint256(keccak256("alice")))); // option token creator / receiver
        bob = address(uint160(uint256(keccak256("bob")))); // option token exerciser
        carol = address(uint160(uint256(keccak256("carol"))));

        // Deploy contracts
        auth = new RolesAuthority(address(this), Authority(address(0))); // owner is this contract for setting permissions
        teller = new FixedStrikeOptionTeller(guardian, auth);

        // Deploy mock tokens
        abc = new MockERC20("ABC", "ABC", 18);
        def = new MockERC20("DEF", "DEF", 18);
        ghi = new MockERC20("GHI", "GHI", 9); // create with 9 decimals to test decimal setting and strike/payout values
        jklmno = new MockERC20("JKLMNO", "JKLMNO", 18); // create token with symbol longer than 5 characters to test token name/symbol bounds

        // Set permissions
        auth.setRoleCapability(uint8(0), address(teller), teller.setProtocolFee.selector, true);
        auth.setRoleCapability(uint8(0), address(teller), teller.claimFees.selector, true);
        auth.setUserRole(guardian, uint8(0), true);

        // Set protocol fee for testing
        vm.prank(guardian);
        teller.setProtocolFee(uint48(500)); // 0.5% fee

        // Mint tokens to users for testing
        abc.mint(alice, 1_000_000 * 1e18);
        def.mint(alice, 1_000_000 * 1e18);
        ghi.mint(alice, 1_000_000 * 1e9);

        abc.mint(bob, 5_000_000 * 1e18);
        def.mint(bob, 5_000_000 * 1e18);
        ghi.mint(bob, 5_000_000 * 1e9);

        // Have users approve teller
        vm.prank(alice);
        abc.approve(address(teller), type(uint256).max);

        vm.prank(alice);
        def.approve(address(teller), type(uint256).max);

        vm.prank(alice);
        ghi.approve(address(teller), type(uint256).max);

        vm.prank(bob);
        abc.approve(address(teller), type(uint256).max);

        vm.prank(bob);
        def.approve(address(teller), type(uint256).max);

        vm.prank(bob);
        ghi.approve(address(teller), type(uint256).max);
    }

    /* ========== HELPER FUNCTIONS ========== */

    /* ========== FIXED STRIKE OPTION TELLER TESTS ========== */
    // DONE
    // Core functionality: deploy, create, exercise, and reclaim option tokens
    // [X] deploy
    //     [X] if option token does not exist, a new option token is deployed
    //         [X] option token parameters are set correctly
    //         [X] option token domain separator is set correctly
    //         [X] option token is added to option tokens mapping via hash
    //         [X] eligible and expiry timestamps are rounded to nearest day
    //         [X] name and symbol strings are set correctly based on their bounds
    //         [X] single param changes result in different option tokens
    //     [X] if option token exists, the existing option token is returned
    //         [X] eligible and expiry timestamps are rounded to nearest day when checking for existing token (i.e. a new token shouldn't be created when different timestamps round to the same value)
    //     [X] invalid parameters cause revert
    // [X] create
    //     [X] revert if option token does not exist. must be deployed.
    //     [X] revert if option token does not match the stored token for the hash. must be deployed by this teller.
    //     [X] revert if current timestamp is past the expiry. cannot mint after expiry.
    //     [X] call option variant
    //         [X] creator sends in correct amount of payout tokens as collateral
    //         [X] correct number of option tokens are minted
    //         [X] reverts if payout token has a fee-on-transfer mechanism (and contract is not whitelisted)
    //     [X] put option variant
    //         [X] creator sends in correct amount of quote tokens as collateral
    //         [X] reverts if quote token has a fee-on-transfer mechanism (and contract is not whitelisted)
    //         [X] correct number of option tokens are minted
    //         [ ] quote amount must not be zero
    // [X] exercise
    //     [X] revert if option token does not exist. must be deployed.
    //     [X] revert if option token does not match the stored token for the hash. must be deployed by this teller.
    //     [X] revert if current timestamp is past the expiry. cannot exercise after expiry.
    //     [X] revert if current timestamp is before the eligible timestamp. cannot exercise before eligible.
    //     [X] call option variant
    //         [X] if caller is option token "receiver", do not require payment of quote tokens to redeem option tokens for payout tokens
    //             [X] correct number of option tokens are burned
    //             [X] receiver's payout token collateral is returned
    //         [X] if caller is not option token "receiver", require payment of quote tokens (at strike price) to redeem option tokens for payout tokens
    //             [X] reverts if quote token has a fee-on-transfer mechanism (and contract is not whitelisted)
    //             [X] caller pays correct amount of quote tokens
    //             [X] correct fee in quote tokens is allocated to protocol
    //             [X] receiver receives correct amount of quote tokens (total minus fee)
    //             [X] correct number of option tokens are burned
    //     [X] put option variant
    //         [X] if caller is option token "receiver", do not require payment of payout tokens to redeem option tokens for quote tokens
    //             [X] correct number of option tokens are burned
    //             [X] receiver's quote token collateral is returned
    //         [X] if caller is not option token "receiver", require payment of payout tokens to redeem option tokens for quote tokens (at strike price)
    //             [X] reverts if payout token has a fee-on-transfer mechanism (and contract is not whitelisted)
    //             [X] caller pays correct amount of payout tokens
    //             [X] correct fee in payout tokens is allocated to protocol
    //             [X] receiver receives correct amount of payout tokens (total minus fee)
    //             [X] correct number of option tokens are burned
    // [X] reclaim
    //     [X] revert if option token does not exist. must be deployed.
    //     [X] revert if option token does not match the stored token for the hash. must be deployed by this teller.
    //     [X] revert if current timestamp is not past the expiry. cannot reclaim before option token expires.
    //     [X] revert if caller is not option token "receiver". only receiver can reclaim.
    //     [ ] revert if collateral has already been reclaimed for the option token.
    //     [X] call option variant
    //         [X] caller receives correct number of payout tokens (extant supply of option tokens)
    //     [X] put option variant
    //         [X] caller receives correct number of quote tokens (extant supply of option tokens)
    //
    // View functions
    // [X] exerciseCost
    //     [X] revert if option token does not exist. must be deployed.
    //     [X] revert if option token does not match the stored token for the hash. must be deployed by this teller.
    //     [X] call option variant
    //         [X] correct amount of quote tokens are returned
    //         [X] quote token address is returned
    //     [X] put option variant
    //         [X] correct amount of payout tokens are returned
    //         [X] payout token address is returned
    // [X] getOptionToken
    //     [X] revert if option token does not exist. must be deployed.
    //     [X] eligible and expiry timestamps are rounded to nearest day when checking for existing token
    //     [X] returns correct option token address for inputs
    // [X] getOptionTokenHash
    //     [X] eligible and expiry timestamps are rounded to nearest day when checking for existing token
    //     [X] option token hash is calculated correctly
    //
    // Admin functions
    // [X] setProtocolFee
    //     [X] revert if caller does not have a role with required permission
    //     [X] revert if fee is greater than 5%
    //     [X] protocol fee is updated correctly
    // [X] claimFees
    //     [X] revert if caller does not have a role with required permission
    //     [X] zero tokens provided - nothing happens
    //     [X] non-zero tokens provided - correct amount of tokens are transferred to provided address per token (current fee balance)
    //
    // TODO think about fuzz testing for token decimals and setting bounds for allowable token decimals in addition to the price decimals bounds
    // Current thought is that it's not worth the gas cost since the strike price is in quote token decimals.
    // Negative price decimals are limited by the token decimals.
    // Positive price decimals are limited by the max uint size. It would theoretically be possible to overflow, but this would not happen in a regular configuration.
    // The only reason this was an issue with the main auction system is because of the debt and control variables being multiplied together.

    /* ========== deploy ========== */

    function test_deploy_tokenDoesNotExist() public {
        // Deploy a new option token
        uint256 strikePrice = 50012 * uint256(10 ** (def.decimals() - 3)); // expect truncation on name and symbol
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        uint48 expectedEligible = (uint48(block.timestamp + 1 days + 1 hours) / 1 days) * 1 days;
        uint48 expectedExpiry = (uint48(block.timestamp + 8 days + 1 hours) / 1 days) * 1 days;

        // Check that parameters on the option token were set correctly
        assertEq(address(optionToken.payout()), address(abc));
        assertEq(address(optionToken.quote()), address(def));
        assertEq(optionToken.eligible(), expectedEligible);
        assertEq(optionToken.expiry(), expectedExpiry);
        assertEq(optionToken.receiver(), alice);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), strikePrice);
        assertEq(optionToken.teller(), address(teller));
        assertEq(
            optionToken.name(),
            string(abi.encodePacked(bytes32("ABC/DEF C 5.001e+1 20220109")))
        );
        assertEq(optionToken.symbol(), string(abi.encodePacked(bytes32("oABC-20220109"))));
        assertEq(optionToken.decimals(), abc.decimals());

        // Check that the domain separator on the option token was set correctly
        assertEq(
            optionToken.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(optionToken.name())),
                    keccak256("1"),
                    block.chainid,
                    address(optionToken)
                )
            )
        );

        // Check that the option token is stored correctly on the teller
        address storedOptionToken = address(
            teller.getOptionToken(
                abc, // ERC20 payoutToken
                def, // ERC20 quoteToken
                uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - 20220102
                uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
                alice, // address receiver
                true, // bool call (true) or put (false)
                strikePrice // uint256 strikePrice
            )
        );
        assertEq(storedOptionToken, address(optionToken));

        bytes32 optionHash = teller.getOptionTokenHash(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );
        assertEq(address(teller.optionTokens(optionHash)), address(optionToken));
    }

    function test_deploy_tokenDoesNotExist_eligibleZero() public {
        // Deploy a new option token
        uint256 strikePrice = 50012 * uint256(10 ** (def.decimals() - 3)); // expect truncation on name and symbol
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - should imply 20220101
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        uint48 expectedEligible = (uint48(block.timestamp) / 1 days) * 1 days;
        uint48 expectedExpiry = (uint48(block.timestamp + 8 days + 1 hours) / 1 days) * 1 days;

        // Check that parameters on the option token were set correctly
        assertEq(address(optionToken.payout()), address(abc));
        assertEq(address(optionToken.quote()), address(def));
        assertEq(optionToken.eligible(), expectedEligible);
        assertEq(optionToken.expiry(), expectedExpiry);
        assertEq(optionToken.receiver(), alice);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), strikePrice);
        assertEq(optionToken.teller(), address(teller));
        assertEq(
            optionToken.name(),
            string(abi.encodePacked(bytes32("ABC/DEF C 5.001e+1 20220109")))
        );
        assertEq(optionToken.symbol(), string(abi.encodePacked(bytes32("oABC-20220109"))));
        assertEq(optionToken.decimals(), abc.decimals());

        // Check that the domain separator on the option token was set correctly
        assertEq(
            optionToken.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes(optionToken.name())),
                    keccak256("1"),
                    block.chainid,
                    address(optionToken)
                )
            )
        );

        // Check that the option token is stored correctly on the teller
        address storedOptionToken = address(
            teller.getOptionToken(
                abc, // ERC20 payoutToken
                def, // ERC20 quoteToken
                uint48(block.timestamp), // uint48 eligible (timestamp) - 20220102
                uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
                alice, // address receiver
                true, // bool call (true) or put (false)
                strikePrice // uint256 strikePrice
            )
        );
        assertEq(storedOptionToken, address(optionToken));

        bytes32 optionHash = teller.getOptionTokenHash(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );
        assertEq(address(teller.optionTokens(optionHash)), address(optionToken));
    }

    function testRevert_deploy_invalidParams() public {
        // Go through each invalid params check and ensure improper values are caught
        uint256 quoteDecimals = def.decimals();

        // Case: payoutToken == address(0)
        bytes memory err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            0,
            abi.encodePacked(address(0))
        );
        vm.expectRevert(err);
        teller.deploy(
            ERC20(address(0)), // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: payoutToken is not a contract
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            0,
            abi.encodePacked(bob)
        );
        vm.expectRevert(err);
        teller.deploy(
            ERC20(bob), // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: quoteToken == address(0)
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            1,
            abi.encodePacked(address(0))
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            ERC20(address(0)), // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: quoteToken is not a contract
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            1,
            abi.encodePacked(bob)
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            ERC20(bob), // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: eligible < block.timestamp
        // Minus 1 second works here with the rounding because the current timestamp is exactly 00:00:00 UTC so moving back one second goes to the previous day
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            2,
            abi.encodePacked((uint48(block.timestamp - 1) / 1 days) * 1 days)
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp - 1), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: expiry < eligible
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            3,
            abi.encodePacked((uint48(block.timestamp + 1 days + 1 hours) / 1 days) * 1 days)
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 2 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 1 days + 1 hours), // uint48 expiry (timestamp) - 20220103
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: expiry == eligible
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 1 days + 1 hours), // uint48 expiry (timestamp) - 20220103
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: expiry - eligible less than min option duration
        // Set min duration to a new value to test
        vm.prank(guardian);
        teller.setMinOptionDuration(uint48(5 days));
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            3,
            abi.encodePacked((uint48(block.timestamp + 3 days + 1 hours) / 1 days) * 1 days)
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 3 days + 1 hours), // uint48 expiry (timestamp) - 20220103
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: receiver == address(0)
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            4,
            abi.encodePacked(address(0))
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            address(0), // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** quoteDecimals // uint256 strikePrice
        );

        // Case: strikePrice == 0
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            6,
            abi.encodePacked(uint256(0))
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            uint256(0) // uint256 strikePrice
        );

        // Case: strikePrice over lower bound (price decimals < -9)
        uint256 strike = 10 ** (quoteDecimals - 10);
        err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            6,
            abi.encodePacked(strike)
        );
        vm.expectRevert(err);
        teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strike // uint256 strikePrice
        );
    }

    function test_deploy_tokenDoesExist_eligibleZero(uint48 expiryDiff_) public {
        vm.assume(expiryDiff_ < uint48(1 days));

        // Deploy a token so there is one with this specific configuration
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Try to deploy another token with the same configuration, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(0), // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );

        // Change expiry timestamp to another value that still roudns to the same day, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(0), // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days) + expiryDiff_, // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );
    }

    function test_deploy_singleParamDiff() public {
        // Check that changing any single parameter (besides timestamps with rounding) results in a new option token

        // Deploy initial option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken baseToken = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Deploy option token with different payout token
        FixedStrikeOptionToken token = teller.deploy(
            ghi,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different quote token
        token = teller.deploy(
            abc,
            ghi,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different eligible timestamp
        token = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 2 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different expiry timestamp
        token = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 9 days),
            alice,
            true,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different receiver
        token = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            bob,
            true,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different isCall
        token = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            false,
            strikePrice
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));

        // Deploy option token with different strike price
        token = teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice + 1
        );

        // Check that the addresses are different
        assertFalse(address(token) == address(baseToken));
    }

    function test_deploy_tokenDoesExist(uint48 eligibleDiff_, uint48 expiryDiff_) public {
        vm.assume(eligibleDiff_ < uint48(1 days));
        vm.assume(expiryDiff_ < uint48(1 days));

        // Deploy a token so there is one with this specific configuration
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Try to deploy another token with the same configuration, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );

        // Change eligible timestamp to another value that still rounds to the same day, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(block.timestamp + 1 days) + eligibleDiff_, // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days + 1 hours), // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );

        // Change expiry timestamp to another value that still roudns to the same day, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(block.timestamp + 1 days + 1 hours), // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days) + expiryDiff_, // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );

        // Change both eligible and expiry timestamps to another value that still rounds to the same day, expect address to be the same
        assertEq(
            address(optionToken),
            address(
                teller.deploy(
                    abc, // ERC20 payoutToken
                    def, // ERC20 quoteToken
                    uint48(block.timestamp + 1 days) + eligibleDiff_, // uint48 eligible (timestamp) - should imply 20220102
                    uint48(block.timestamp + 8 days) + expiryDiff_, // uint48 expiry (timestamp) - 20220109
                    alice, // address receiver
                    true, // bool call (true) or put (false)
                    5 * 10 ** def.decimals() // uint256 strikePrice
                )
            )
        );
    }

    function test_deploy_decimals() public {
        // Create an option token where the payout decimals are greater than the quote token decimals
        uint256 strikePrice = 5 * 10 ** ghi.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc,
            ghi,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that parameters on the option token were set correctly
        assertEq(address(optionToken.payout()), address(abc));
        assertEq(address(optionToken.quote()), address(ghi));
        assertEq(optionToken.strike(), strikePrice);
        assertEq(
            optionToken.name(),
            string(abi.encodePacked(bytes32("ABC/GHI C 5.000e+0 20220109")))
        );
        assertEq(optionToken.symbol(), string(abi.encodePacked(bytes32("oABC-20220109"))));
        assertEq(optionToken.decimals(), abc.decimals());

        // Create an option token where the payout decimals are less than the quote token decimals
        strikePrice = 5 * 10 ** abc.decimals();
        optionToken = teller.deploy(
            ghi,
            abc,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that parameters on the option token were set correctly
        assertEq(address(optionToken.payout()), address(ghi));
        assertEq(address(optionToken.quote()), address(abc));
        assertEq(optionToken.strike(), strikePrice);
        assertEq(
            optionToken.name(),
            string(abi.encodePacked(bytes32("GHI/ABC C 5.000e+0 20220109")))
        );
        assertEq(optionToken.symbol(), string(abi.encodePacked(bytes32("oGHI-20220109"))));
        assertEq(optionToken.decimals(), ghi.decimals());
    }

    /* ========== create ========== */

    function testRevert_create_tokenDoesNotExist() public {
        // Create token that isn't issued by the teller
        // Using this mock since it implements the getOptionParameters function required by the create function
        uint256 strikePrice = 5 * 10 ** def.decimals();
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(teller),
            strikePrice
        );

        // Try to create option tokens, expect revert
        bytes32 optionHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );
        bytes memory err = abi.encodeWithSignature("Teller_TokenDoesNotExist(bytes32)", optionHash);
        vm.expectRevert(err);
        teller.create(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testRevert_create_tokenDoesNotMatchStored() public {
        // Deploy a real option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Deploy a malicious option token that has the same configuration
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(bob),
            strikePrice
        );

        // Try to create option tokens by passing in the malicious option token, but expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(badToken)
        );
        vm.expectRevert(err);
        teller.create(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testFail_create_invalidOptionToken() public {
        // Try to create option tokens with a contract that doesn't conform to the required interface, expect fail
        teller.create(FixedStrikeOptionToken(address(abc)), 1);
    }

    function testRevert_create_optionExpired() public {
        // Deploy an option token
        uint48 expiry = uint48(block.timestamp + 8 days);
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - should imply 20220102
            expiry, // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Warp forward in time past the expiry
        vm.warp(block.timestamp + 9 days);

        // Try to create option tokens, expect revert
        bytes memory err = abi.encodeWithSignature("Teller_OptionExpired(uint48)", expiry);
        vm.expectRevert(err);
        teller.create(optionToken, 1);
    }

    function test_create_call() public {
        // Deploy call option token
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        uint256 startPayoutBalance = abc.balanceOf(alice);
        uint256 startOptionBalance = optionToken.balanceOf(alice);
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Check that balances have changed correctly
        assertEq(abc.balanceOf(alice), startPayoutBalance - amount);
        assertEq(optionToken.balanceOf(alice), startOptionBalance + amount);
    }

    function testRevert_create_call_feeOnTransferToken() public {
        // Create a fee on transfer token with 1% transfer fee
        MockFOTERC20 fot = new MockFOTERC20("Fee on Transfer", "FOT", 18, address(carol), 1e3);
        uint256 amount = 100 * 1e18;
        fot.mint(alice, amount);
        vm.prank(alice);
        fot.approve(address(teller), amount);

        // Deploy a call option token with the fot token as the payout token
        FixedStrikeOptionToken optionToken = teller.deploy(
            fot,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            5 * 10 ** def.decimals()
        );

        // Try to create option tokens by depositing the fot token, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(fot)
        );
        vm.expectRevert(err);
        vm.prank(alice);
        teller.create(optionToken, amount);
    }

    function test_create_put() public {
        // Deploy put option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (quote tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        uint256 collateralAmount = (amount * strikePrice) / 10 ** abc.decimals();
        uint256 startQuoteBalance = def.balanceOf(alice);
        uint256 startOptionBalance = optionToken.balanceOf(alice);
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Check that balances have changed correctly
        assertEq(def.balanceOf(alice), startQuoteBalance - collateralAmount);
        assertEq(optionToken.balanceOf(alice), startOptionBalance + amount);
    }

    function testRevert_create_put_feeOnTransferToken() public {
        // Create a fee on transfer token with 1% transfer fee
        MockFOTERC20 fot = new MockFOTERC20("Fee on Transfer", "FOT", 18, address(carol), 1e3);
        uint256 collateralAmount = 500 * 1e18;
        fot.mint(alice, collateralAmount);
        vm.prank(alice);
        fot.approve(address(teller), collateralAmount);

        // Deploy a put option token with the fot token as the quote token
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc,
            fot,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            false,
            5 * 1e18
        );

        // Try to create option tokens by depositing the fot token, expect revert
        uint256 amount = 100 * 10 ** abc.decimals();
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(fot)
        );
        vm.expectRevert(err);
        vm.prank(alice);
        teller.create(optionToken, amount);
    }

    function test_create_put_quoteAmount(uint256 amount_) public {
        // Create new ERC20 token token with 6 decimals
        MockERC20 pqr = new MockERC20("PQR", "PQR", 6);
        pqr.mint(alice, type(uint256).max);
        vm.prank(alice);
        pqr.approve(address(teller), type(uint256).max);

        // Deploy put option token
        uint256 strikePrice = 5 * 10 ** 6;
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            pqr, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (quote tokens)
        uint256 collateralAmount = amount_.mulDivUp(strikePrice, 10 ** 18);
        uint256 startQuoteBalance = pqr.balanceOf(alice);
        uint256 startOptionBalance = optionToken.balanceOf(alice);
        if (collateralAmount == 0) {
            // Should revert if collateral amount required is zero
            bytes memory err = abi.encodeWithSignature("Teller_InvalidAmount()");
            vm.expectRevert(err);
            vm.prank(alice);
            teller.create(optionToken, amount_);
        } else {
            vm.prank(alice);
            teller.create(optionToken, amount_);
            // Check that balances have changed correctly
            assertEq(pqr.balanceOf(alice), startQuoteBalance - collateralAmount);
            assertEq(optionToken.balanceOf(alice), startOptionBalance + amount_);
        }
    }

    /* ========== exercise ========== */

    function testRevert_exercise_tokenDoesNotExist() public {
        // Create token that isn't issued by the teller
        // Using this mock since it implements the getOptionParameters function required by the create function
        uint256 strikePrice = 5 * 10 ** def.decimals();
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(teller),
            strikePrice
        );

        // Try to exercise option tokens, expect revert
        bytes32 optionHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );
        bytes memory err = abi.encodeWithSignature("Teller_TokenDoesNotExist(bytes32)", optionHash);
        vm.expectRevert(err);
        teller.exercise(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testRevert_exercise_tokenDoesNotMatchStored() public {
        // Deploy a real option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Deploy a malicious option token that has the same configuration
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(bob),
            strikePrice
        );

        // Try to exercise option tokens by passing in the malicious option token, but expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(badToken)
        );
        vm.expectRevert(err);
        teller.exercise(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testFail_exercise_invalidOptionToken() public {
        // Try to exercise option tokens with a contract that doesn't conform to the required interface, expect fail
        teller.exercise(FixedStrikeOptionToken(address(abc)), 1);
    }

    function testRevert_exercise_optionNotEligible() public {
        // Deploy an option token
        uint48 eligible = uint48(block.timestamp + 2 days);
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            eligible, // uint48 eligible (timestamp) - should imply 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Try to exercise option tokens, expect revert
        bytes memory err = abi.encodeWithSignature("Teller_NotEligible(uint48)", eligible);
        vm.expectRevert(err);
        teller.exercise(optionToken, 1);
    }

    function testRevert_exercise_optionExpired() public {
        // Deploy an option token
        uint48 expiry = uint48(block.timestamp + 8 days);
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - should imply 20220102
            expiry, // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Warp forward in time past the expiry
        vm.warp(block.timestamp + 9 days);

        // Try to exercise option tokens, expect revert
        bytes memory err = abi.encodeWithSignature("Teller_OptionExpired(uint48)", expiry);
        vm.expectRevert(err);
        teller.exercise(optionToken, 1);
    }

    function test_exercise_call() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send option tokens to bob
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        assertEq(optionToken.balanceOf(bob), amount);

        // Exercise option tokens
        uint256 paymentAmount = (amount * strikePrice) / 10 ** abc.decimals();
        uint256 aliceQuoteStart = def.balanceOf(alice);
        uint256 bobQuoteStart = def.balanceOf(bob);
        uint256 tellerQuoteStart = def.balanceOf(address(teller));
        uint256 bobPayoutStart = abc.balanceOf(bob);
        uint256 tellerPayoutStart = abc.balanceOf(address(teller));

        vm.prank(bob);
        teller.exercise(optionToken, amount);

        // Check that balance updates are correct
        // - Alice (as receiver) gets the paymentAmount (minus fees) of quoteTokens
        // - Bob pays the paymentAmount of quoteTokens and receives the amount of payoutTokens. Bob's option tokens are burned when exercised.
        // - Teller gets the fee amount of quoteTokens, this should be stored in the fees mapping for the protocol. Teller pays out the amount of payoutTokens.
        uint256 feeAmount = (paymentAmount * uint256(teller.protocolFee())) /
            uint256(teller.FEE_DECIMALS());
        assertEq(def.balanceOf(alice), aliceQuoteStart + paymentAmount - feeAmount);
        assertEq(def.balanceOf(bob), bobQuoteStart - paymentAmount);
        assertEq(def.balanceOf(address(teller)), tellerQuoteStart + feeAmount);
        assertEq(teller.fees(def), feeAmount);
        assertEq(abc.balanceOf(bob), bobPayoutStart + amount);
        assertEq(abc.balanceOf(address(teller)), tellerPayoutStart - amount);
        assertEq(optionToken.balanceOf(bob), 0);
    }

    function testRevert_exercise_call_feeOnTransferToken() public {
        // Create a fee on transfer token with 1% transfer fee
        MockFOTERC20 fot = new MockFOTERC20("Fee on Transfer", "FOT", 18, address(carol), 1e3);
        uint256 paymentAmount = 500 * 1e18;
        fot.mint(bob, paymentAmount);
        vm.prank(bob);
        fot.approve(address(teller), paymentAmount);

        // Deploy a call option token with the fot token as the quote token
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc,
            fot,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            5 * 1e18
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send option tokens to bob
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        assertEq(optionToken.balanceOf(bob), amount);

        // Try to exercise option tokens by paying the fot token, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(fot)
        );
        vm.expectRevert(err);
        vm.prank(bob);
        teller.exercise(optionToken, amount);
    }

    function test_exercise_call_receiver() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        assertEq(optionToken.balanceOf(alice), amount);

        // Exercise option tokens as receiver
        // Shouldn't have to pay exercise cost. Effectively, they are unwrapping option tokens for the underlying collateral
        uint256 alicePayoutStart = abc.balanceOf(alice);
        uint256 tellerPayoutStart = abc.balanceOf(address(teller));

        vm.prank(alice);
        teller.exercise(optionToken, amount);

        // Check that balance updates are correct
        // - Alice receives the amount of payoutTokens and her option tokens are burned,.
        // - Teller pays out the amount of payoutTokens.
        assertEq(abc.balanceOf(alice), alicePayoutStart + amount);
        assertEq(abc.balanceOf(address(teller)), tellerPayoutStart - amount);
        assertEq(optionToken.balanceOf(alice), 0);
    }

    function test_exercise_put() public {
        // Deploy put option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (quote tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send option tokens to bob
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        assertEq(optionToken.balanceOf(bob), amount);

        // Exercise option tokens
        uint256 receiveAmount = (amount * strikePrice) / 10 ** abc.decimals();
        uint256 alicePayoutStart = abc.balanceOf(alice);
        uint256 bobPayoutStart = abc.balanceOf(bob);
        uint256 tellerPayoutStart = abc.balanceOf(address(teller));
        uint256 bobQuoteStart = def.balanceOf(bob);
        uint256 tellerQuoteStart = def.balanceOf(address(teller));

        vm.prank(bob);
        teller.exercise(optionToken, amount);

        // Check that balance updates are correct
        // - Alice (as receiver) gets the amount (minus fees) of payoutTokens
        // - Bob pays the amount of payoutTokens and gets the receiveAmount of quoteTokens. Bob's option tokens are burned when exercised.
        // - Teller gets the fee amount of payoutTokens, this should be stored in the fees mapping for the protocol. Teller pays out the amount of quoteTokens.
        uint256 feeAmount = (amount * uint256(teller.protocolFee())) /
            uint256(teller.FEE_DECIMALS());
        assertEq(abc.balanceOf(alice), alicePayoutStart + amount - feeAmount);
        assertEq(abc.balanceOf(bob), bobPayoutStart - amount);
        assertEq(abc.balanceOf(address(teller)), tellerPayoutStart + feeAmount);
        assertEq(teller.fees(abc), feeAmount);
        assertEq(def.balanceOf(bob), bobQuoteStart + receiveAmount);
        assertEq(def.balanceOf(address(teller)), tellerQuoteStart - receiveAmount);
        assertEq(optionToken.balanceOf(bob), 0);
    }

    function testRevert_exercise_put_feeOnTransferToken() public {
        // Create a fee on transfer token with 1% transfer fee
        MockFOTERC20 fot = new MockFOTERC20("Fee on Transfer", "FOT", 18, address(carol), 1e3);
        uint256 amount = 100 * 1e18;
        fot.mint(bob, amount);
        vm.prank(bob);
        fot.approve(address(teller), amount);

        // Deploy a put option token with the fot token as the payout token
        FixedStrikeOptionToken optionToken = teller.deploy(
            fot,
            def,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            false,
            5 * 1e18
        );

        // Mint option tokens by depositing collateral (quote tokens)
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send option tokens to bob
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        assertEq(optionToken.balanceOf(bob), amount);

        // Try to exercise option tokens by paying the fot token, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(fot)
        );
        vm.expectRevert(err);
        vm.prank(bob);
        teller.exercise(optionToken, amount);
    }

    function test_exercise_put_receiver() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (quote tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        assertEq(optionToken.balanceOf(alice), amount);

        // Exercise option tokens as receiver
        // Shouldn't have to pay exercise cost. Effectively, they are unwrapping option tokens for the underlying collateral
        uint256 receiveAmount = (amount * strikePrice) / 10 ** abc.decimals();
        uint256 aliceQuoteStart = def.balanceOf(alice);
        uint256 tellerQuoteStart = def.balanceOf(address(teller));

        vm.prank(alice);
        teller.exercise(optionToken, amount);

        // Check that balance updates are correct
        // - Alice receives the amount of quoteTokens and her option tokens are burned.
        // - Teller pays out the amount of quoteTokens.
        assertEq(def.balanceOf(alice), aliceQuoteStart + receiveAmount);
        assertEq(def.balanceOf(address(teller)), tellerQuoteStart - receiveAmount);
        assertEq(optionToken.balanceOf(alice), 0);
    }

    /* ========== reclaim ========== */
    function testRevert_reclaim_tokenDoesNotExist() public {
        // Create token that isn't issued by the teller
        // Using this mock since it implements the getOptionParameters function required by the reclaim function
        uint256 strikePrice = 5 * 10 ** def.decimals();
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(teller),
            strikePrice
        );

        // Try to reclaim option tokens, expect revert
        bytes32 optionHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );
        bytes memory err = abi.encodeWithSignature("Teller_TokenDoesNotExist(bytes32)", optionHash);
        vm.expectRevert(err);
        teller.reclaim(FixedStrikeOptionToken(address(badToken)));
    }

    function testRevert_reclaim_tokenDoesNotMatchStored() public {
        // Deploy a real option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Deploy a malicious option token that has the same configuration
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(bob),
            strikePrice
        );

        // Try to reclaim option tokens by passing in the malicious option token, but expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(badToken)
        );
        vm.expectRevert(err);
        teller.reclaim(FixedStrikeOptionToken(address(badToken)));
    }

    function testFail_reclaim_invalidOptionToken() public {
        // Try to reclaim option tokens with a contract that doesn't conform to the required interface, expect fail
        teller.reclaim(FixedStrikeOptionToken(address(abc)));
    }

    function testRevert_reclaim_optionNotExpired() public {
        // Deploy an option token
        uint48 expiry = uint48(block.timestamp + 8 days);
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            expiry, // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            5 * 10 ** def.decimals() // uint256 strikePrice
        );

        // Try to reclaim option tokens, expect revert
        bytes memory err = abi.encodeWithSignature("Teller_NotExpired(uint48)", expiry);
        vm.expectRevert(err);
        teller.reclaim(optionToken);
    }

    function testFuzz_reclaim_onlyReceiver(address other_) public {
        vm.assume(other_ != alice);

        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        assertEq(optionToken.balanceOf(alice), amount);

        // Send option tokens to another user (receiver doesn't have to hold them for reclaiming)
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        // Warp past expiry
        vm.warp(block.timestamp + 9 days);

        // Try to reclaim collateral with an address that isn't the receiver, expect revert
        bytes memory err = abi.encodeWithSignature("Teller_NotAuthorized()");
        vm.expectRevert(err);
        vm.prank(other_);
        teller.reclaim(optionToken);

        // Try to reclaim collateral with the receiver, expect success
        vm.prank(alice);
        teller.reclaim(optionToken);
    }

    function test_reclaim_call() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send the option tokens to another user (receiver doesn't need to hold)
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        // Warp forward past expiry
        vm.warp(block.timestamp + 9 days);

        // Reclaim collateral as receiver
        uint256 alicePayoutStart = abc.balanceOf(alice);
        uint256 tellerPayoutStart = abc.balanceOf(address(teller));

        vm.prank(alice);
        teller.reclaim(optionToken);

        // Check that balance updates are correct
        // - Alice receives the amount of payoutTokens.
        // - Teller pays out the amount of payoutTokens.
        assertEq(abc.balanceOf(alice), alicePayoutStart + amount);
        assertEq(abc.balanceOf(address(teller)), tellerPayoutStart - amount);
        // Note: option tokens are not burned on a reclaim, they just remain in place since they are expired
        assertEq(optionToken.balanceOf(bob), amount);
    }

    function test_reclaim_put() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (quote tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Send the option tokens to another user (receiver doesn't need to hold)
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        // Warp forward past expiry
        vm.warp(block.timestamp + 9 days);

        // Reclaim collateral as receiver
        uint256 receiveAmount = (amount * strikePrice) / 10 ** abc.decimals();
        uint256 aliceQuoteStart = def.balanceOf(alice);
        uint256 tellerQuoteStart = def.balanceOf(address(teller));

        vm.prank(alice);
        teller.reclaim(optionToken);

        // Check that balance updates are correct
        // - Alice receives the receiveAmount of quoteTokens.
        // - Teller pays out the receiveAmount of quoteTokens.
        assertEq(def.balanceOf(alice), aliceQuoteStart + receiveAmount);
        assertEq(def.balanceOf(address(teller)), tellerQuoteStart - receiveAmount);
        // Note: option tokens are not burned on a reclaim, they just remain in place since they are expired
        assertEq(optionToken.balanceOf(bob), amount);
    }

    function testRevert_reclaim_multipleTimes() public {
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Deploy a second option token with the same params and different receiver
        FixedStrikeOptionToken optionToken2 = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            bob, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Mint option tokens by depositing collateral (payout tokens)
        uint256 amount = 100 * 10 ** abc.decimals();
        vm.prank(alice);
        teller.create(optionToken, amount);

        // Create some optionToken2 so there will be additional payout tokens in the teller
        vm.prank(bob);
        teller.create(optionToken2, amount);

        // Send the option tokens to another user (receiver doesn't need to hold)
        vm.prank(alice);
        optionToken.transfer(bob, amount);

        // Warp forward past expiry
        vm.warp(block.timestamp + 9 days);

        // Reclaim collateral as receiver
        uint256 alicePayoutStart = abc.balanceOf(alice);
        uint256 tellerPayoutStart = abc.balanceOf(address(teller));

        vm.prank(alice);
        teller.reclaim(optionToken);

        // Check that balance updates are correct
        // - Alice receives the amount of payoutTokens.
        // - Teller pays out the amount of payoutTokens.
        assertEq(abc.balanceOf(alice), alicePayoutStart + amount);
        assertEq(abc.balanceOf(address(teller)), tellerPayoutStart - amount);
        // Note: option tokens are not burned on a reclaim, they just remain in place since they are expired
        assertEq(optionToken.balanceOf(bob), amount);

        // Try to reclaim again, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_AlreadyReclaimed(address)",
            address(optionToken)
        );
        vm.expectRevert(err);
        vm.prank(alice);
        teller.reclaim(optionToken);
    }

    /* ========== exerciseCost ========== */
    function testRevert_exerciseCost_tokenDoesNotExist() public {
        // Create token that isn't issued by the teller
        // Using this mock since it implements the getOptionParameters function required by the exerciseCost function
        uint256 strikePrice = 5 * 10 ** def.decimals();
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(teller),
            strikePrice
        );

        // Try to get exercise cost for the malicious option token, expect revert
        bytes32 optionHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );
        bytes memory err = abi.encodeWithSignature("Teller_TokenDoesNotExist(bytes32)", optionHash);
        vm.expectRevert(err);
        teller.exerciseCost(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testRevert_exerciseCost_tokenDoesNotMatchStored() public {
        // Deploy a real option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        teller.deploy(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Deploy a malicious option token that has the same configuration
        MaliciousOptionToken badToken = new MaliciousOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            address(bob),
            strikePrice
        );

        // Try to get exercise cost for the malicious option token, but expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_UnsupportedToken(address)",
            address(badToken)
        );
        vm.expectRevert(err);
        teller.exerciseCost(FixedStrikeOptionToken(address(badToken)), 1);
    }

    function testFail_exerciseCost_invalidOptionToken() public view {
        // Try to get the exercise cost for an option token that doesn't conform to the required interface, expect fail
        teller.exerciseCost(FixedStrikeOptionToken(address(abc)), 1);
    }

    function testFuzz_exerciseCost_call(uint256 amount_) public {
        if (amount_ > type(uint256).max / 5) return;
        // Deploy call option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Get the exercise cost for an arbitrary number of option tokens
        (ERC20 token, uint256 cost) = teller.exerciseCost(optionToken, amount_);

        // Check that the token is the quote token and the cost is the amount times the strike price in quote decimals
        assertEq(address(token), address(def));
        assertEq(cost, amount_.mulDiv(strikePrice, 10 ** abc.decimals()));
    }

    function testFuzz_exerciseCost_put(uint256 amount_) public {
        // Deploy put option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken optionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Get the exercise cost for an arbitrary number of option tokens
        (ERC20 token, uint256 cost) = teller.exerciseCost(optionToken, amount_);

        // Check that the token is the payout token and the cost is the amount
        assertEq(address(token), address(abc));
        assertEq(cost, amount_);
    }

    /* ========== getOptionToken ========== */
    function testRevert_getOptionToken_tokenDoesNotExist() public {
        // Try to get option token that hasn't been deployed, expect revert
        uint256 strikePrice = 5 * 10 ** def.decimals();
        bytes32 optionHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );
        bytes memory err = abi.encodeWithSignature("Teller_TokenDoesNotExist(bytes32)", optionHash);
        vm.expectRevert(err);
        teller.getOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );
    }

    function test_getOptionToken() public {
        // Deploy an option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken expOptionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Call getOptionToken with the same parameters
        FixedStrikeOptionToken optionToken = teller.getOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that the address is the same
        assertEq(address(optionToken), address(expOptionToken));
    }

    function testFuzz_getOptionToken_roundedTimestamps(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) public {
        vm.assume(eligibleDiff_ < uint48(1 days));
        vm.assume(expiryDiff_ < uint48(1 days));

        // Deploy an option token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        FixedStrikeOptionToken expOptionToken = teller.deploy(
            abc, // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(block.timestamp + 1 days), // uint48 eligible (timestamp) - 20220102
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Call getOptionToken with the same parameters, but include the difference in timestamps
        FixedStrikeOptionToken optionToken = teller.getOptionToken(
            abc,
            def,
            uint48(block.timestamp + 1 days) + eligibleDiff_,
            uint48(block.timestamp + 8 days) + expiryDiff_,
            alice,
            true,
            strikePrice
        );

        // Check that the address is the same
        assertEq(address(optionToken), address(expOptionToken));
    }

    /* ========== getOptionTokenHash ========== */
    function test_getOptionTokenHash() public {
        // Calculate an expected hash for the option token params
        uint256 strikePrice = 5 * 10 ** def.decimals();
        bytes32 expHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );

        // Call getOptionTokenHash with the same parameters
        bytes32 optionHash = teller.getOptionTokenHash(
            abc,
            def,
            uint48(block.timestamp + 1 days),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            strikePrice
        );

        // Check that the hash is the same
        assertEq(expHash, optionHash);
    }

    function testFuzz_getOptionTokenHash_roundedTimestamps(
        uint48 eligibleDiff_,
        uint48 expiryDiff_
    ) public {
        vm.assume(eligibleDiff_ < uint48(1 days));
        vm.assume(expiryDiff_ < uint48(1 days));

        // Calculate an expected hash for the option token params
        uint256 strikePrice = 5 * 10 ** def.decimals();
        bytes32 expHash = keccak256(
            abi.encodePacked(
                abc,
                def,
                uint48(block.timestamp + 1 days),
                uint48(block.timestamp + 8 days),
                alice,
                true,
                strikePrice
            )
        );

        // Call getOptionTokenHash with the same parameters plus the timestamp diffs
        bytes32 optionHash = teller.getOptionTokenHash(
            abc,
            def,
            uint48(block.timestamp + 1 days) + eligibleDiff_,
            uint48(block.timestamp + 8 days) + expiryDiff_,
            alice,
            true,
            strikePrice
        );

        // Check that the hash is the same
        assertEq(expHash, optionHash);
    }

    /* ========== setProtocolFee ========== */

    function testFuzz_setProtocolFee_onlyAuthorized(address other_) public {
        vm.assume(other_ != guardian);

        // Try to change the protocol fee with an unauthorized address, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        teller.setProtocolFee(0);

        // Try to change the protocol fee as guardian (permissioned), expect success
        vm.prank(guardian);
        teller.setProtocolFee(100); // 0.1%

        // Check that the protocol fee is updated
        assertEq(teller.protocolFee(), 100);
    }

    function testRevert_setProtocolFee_tooHigh(uint48 fee_) public {
        vm.assume(fee_ > uint48(5e3));

        // Try to set the protocol fee to above 5%, expect revert
        bytes memory err = abi.encodeWithSignature(
            "Teller_InvalidParams(uint256,bytes)",
            0,
            abi.encodePacked(fee_)
        );
        vm.expectRevert(err);
        vm.prank(guardian);
        teller.setProtocolFee(fee_);
    }

    function testFuzz_setProtocolFee(uint48 fee_) public {
        vm.assume(fee_ <= uint48(5e3));

        // Try to change the protocol fee as guardian (permissioned), expect success
        vm.prank(guardian);
        teller.setProtocolFee(fee_);

        // Check that the protocol fee is updated
        assertEq(teller.protocolFee(), fee_);
    }

    /* ========== claimFees ========== */
    function _generateFees() internal {
        // Deploy, create, and exercise option tokens to generate fees in different assets

        // Deploy
        FixedStrikeOptionToken callOptionToken = teller.deploy(
            abc,
            def,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            5 * 10 ** def.decimals()
        );

        FixedStrikeOptionToken putOptionToken = teller.deploy(
            abc,
            def,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            false,
            5 * 10 ** def.decimals()
        );

        FixedStrikeOptionToken callOptionToken2 = teller.deploy(
            abc,
            ghi,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            true,
            5 * 10 ** ghi.decimals()
        );

        FixedStrikeOptionToken putOptionToken2 = teller.deploy(
            abc,
            ghi,
            uint48(0),
            uint48(block.timestamp + 8 days),
            alice,
            false,
            5 * 10 ** ghi.decimals()
        );

        // Create
        vm.startPrank(bob);
        teller.create(callOptionToken, 100e18);
        teller.create(putOptionToken, 100e18);
        teller.create(callOptionToken2, 100e18);
        teller.create(putOptionToken2, 100e18);
        vm.stopPrank();

        // Exercise
        vm.startPrank(bob);
        teller.exercise(callOptionToken, 100e18);
        teller.exercise(putOptionToken, 100e18);
        teller.exercise(callOptionToken2, 100e18);
        teller.exercise(putOptionToken2, 100e18);
        vm.stopPrank();

        // Fees generated from this should be:
        // 0.5% * 100e18 * 2 = 1e18 abc tokens (from both put options)
        // 0.5% * 500e18 = 2.5e18 def tokens (from callOptionToken)
        // 0.5% * 500e18 = 2.5e9 ghi tokens (from callOptionToken2)
    }

    function testFuzz_claimFees_onlyAuthorized(address other_) public {
        vm.assume(other_ != guardian);

        // Create and exercise some option tokens to generate fees
        _generateFees();

        ERC20[] memory feeTokens = new ERC20[](3);
        feeTokens[0] = abc;
        feeTokens[1] = def;
        feeTokens[2] = ghi;

        // Try to claim fees with an unauthorized address, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        teller.claimFees(feeTokens, other_);

        // Try to claim fees as guardian (permissioned), expect success
        vm.prank(guardian);
        teller.claimFees(feeTokens, guardian);
    }

    function test_claimFees_zeroTokens() public {
        // Create and exercise some option tokens to generate fees
        _generateFees();

        ERC20[] memory feeTokens = new ERC20[](0);

        // Store start balances of tokens to check that they are not changed
        uint256[] memory startBalances = new uint256[](3);
        startBalances[0] = abc.balanceOf(address(this));
        startBalances[1] = def.balanceOf(address(this));
        startBalances[2] = ghi.balanceOf(address(this));

        // Try to claim fees with no tokens, expect success, but nothing should happen
        vm.prank(guardian);
        teller.claimFees(feeTokens, address(this));

        // Check that the balances of the tokens are unchanged
        assertEq(abc.balanceOf(address(this)), startBalances[0]);
        assertEq(def.balanceOf(address(this)), startBalances[1]);
        assertEq(ghi.balanceOf(address(this)), startBalances[2]);
    }

    function test_claimFees_oneToken() public {
        // Create and exercise some option tokens to generate fees
        _generateFees();

        ERC20[] memory feeTokens = new ERC20[](1);
        feeTokens[0] = abc;

        // Store start balances of tokens to check that they are changed
        uint256[] memory startBalances = new uint256[](3);
        startBalances[0] = abc.balanceOf(address(this));
        startBalances[1] = def.balanceOf(address(this));
        startBalances[2] = ghi.balanceOf(address(this));

        // Try to claim fees with one token, expect success
        vm.prank(guardian);
        teller.claimFees(feeTokens, address(this));

        // Check that the balances of the tokens are changed
        assertEq(abc.balanceOf(address(this)), startBalances[0] + 1e18);
        assertEq(def.balanceOf(address(this)), startBalances[1]);
        assertEq(ghi.balanceOf(address(this)), startBalances[2]);
    }

    function test_claimFees_manyTokens() public {
        // Create and exercise some option tokens to generate fees
        _generateFees();

        ERC20[] memory feeTokens = new ERC20[](3);
        feeTokens[0] = abc;
        feeTokens[1] = def;
        feeTokens[2] = ghi;

        // Store start balances of tokens to check that they are changed
        uint256[] memory startBalances = new uint256[](3);
        startBalances[0] = abc.balanceOf(address(this));
        startBalances[1] = def.balanceOf(address(this));
        startBalances[2] = ghi.balanceOf(address(this));

        // Try to claim fees with many tokens, expect success
        vm.prank(guardian);
        teller.claimFees(feeTokens, address(this));

        // Check that the balances of the tokens are changed
        assertEq(abc.balanceOf(address(this)), startBalances[0] + 1e18);
        assertEq(def.balanceOf(address(this)), startBalances[1] + 25e17);
        assertEq(ghi.balanceOf(address(this)), startBalances[2] + 25e8);
    }

    function test_claimFees_noFees() public {
        // Create and exercise some option tokens to generate fees
        _generateFees();

        ERC20[] memory feeTokens = new ERC20[](1);
        feeTokens[0] = jklmno;

        // Store start balances of tokens to check that they are not changed
        uint256[] memory startBalances = new uint256[](4);
        startBalances[0] = abc.balanceOf(address(this));
        startBalances[1] = def.balanceOf(address(this));
        startBalances[2] = ghi.balanceOf(address(this));
        startBalances[3] = jklmno.balanceOf(address(this));

        // Try to claim fees for token with no fees stored, expect success, but nothing should happen
        vm.prank(guardian);
        teller.claimFees(feeTokens, address(this));

        // Check that the balances of the tokens are unchanged
        assertEq(abc.balanceOf(address(this)), startBalances[0]);
        assertEq(def.balanceOf(address(this)), startBalances[1]);
        assertEq(ghi.balanceOf(address(this)), startBalances[2]);
        assertEq(jklmno.balanceOf(address(this)), startBalances[3]);
    }

    /* ========== MALICIOUS DECIMAL TESTS ========== */
    // Idea: ensure that a token which changes its decimals can't exploit the teller
    // by changing its decimals to a new value.

    function test_call_correctAmounts_payoutTokenChange() public {
        // Create malicious decimal token
        MaliciousDecimalToken mal = new MaliciousDecimalToken("Changeling", "CHG", 18);
        mal.mint(alice, 1_000_000 * 1e18);
        vm.prank(alice);
        mal.approve(address(teller), type(uint256).max);

        // Deploy call option token with malicious token as payout token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        vm.prank(alice);
        FixedStrikeOptionToken optionToken = teller.deploy(
            ERC20(address(mal)), // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            true, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Create option tokens by depositing collateral (payout tokens) and send to user
        vm.prank(alice);
        teller.create(optionToken, 1000 * 1e18);
        vm.prank(alice);
        optionToken.transfer(bob, 1000 * 1e18);

        // Change decimals of payout token to a small number to try to increase quote token exercise cost
        mal.setDecimals(6);

        // Get price of exercise as user, expect it to be correct based on initial decimals
        (, uint256 cost) = teller.exerciseCost(optionToken, 1000 * 1e18);
        assertEq(cost, (1000 * 1e18 * strikePrice) / 1e18);

        // Exercise option tokens as user, expect balance changes to still be correct based on initial decimals
        uint256 bobQuoteStart = def.balanceOf(bob);
        uint256 bobPayoutStart = mal.balanceOf(bob);
        vm.prank(bob);
        teller.exercise(optionToken, 1000 * 1e18);
        assertEq(def.balanceOf(bob), bobQuoteStart - cost);
        assertEq(mal.balanceOf(bob), bobPayoutStart + 1000 * 1e18);
    }

    function test_put_correctAmounts_payoutTokenChange() public {
        // Create malicious decimal token
        MaliciousDecimalToken mal = new MaliciousDecimalToken("Changeling", "CHG", 18);
        mal.mint(bob, 1_000_000 * 1e18);
        vm.prank(bob);
        mal.approve(address(teller), type(uint256).max);

        // Deploy call option token with malicious token as payout token
        uint256 strikePrice = 5 * 10 ** def.decimals();
        vm.prank(alice);
        FixedStrikeOptionToken optionToken = teller.deploy(
            ERC20(address(mal)), // ERC20 payoutToken
            def, // ERC20 quoteToken
            uint48(0), // uint48 eligible (timestamp) - today
            uint48(block.timestamp + 8 days), // uint48 expiry (timestamp) - 20220109
            alice, // address receiver
            false, // bool call (true) or put (false)
            strikePrice // uint256 strikePrice
        );

        // Change decimals of payout token to a large number to try to decrease the quote token collateral required
        mal.setDecimals(36);

        // Create option tokens by depositing collateral (payout tokens) and send to user
        vm.prank(alice);
        teller.create(optionToken, 1000 * 1e18);
        vm.prank(alice);
        optionToken.transfer(bob, 1000 * 1e18);

        // Exercise option tokens as user, expect balance changes to still be correct based on initial decimals
        uint256 bobQuoteStart = def.balanceOf(bob);
        uint256 bobPayoutStart = mal.balanceOf(bob);
        vm.prank(bob);
        teller.exercise(optionToken, 1000 * 1e18);
        assertEq(def.balanceOf(bob), bobQuoteStart + (1000 * 1e18 * strikePrice) / 1e18);
        assertEq(mal.balanceOf(bob), bobPayoutStart - 1000 * 1e18);
    }
}
