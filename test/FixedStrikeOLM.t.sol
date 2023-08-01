// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockBondOracle} from "test/mocks/MockBondOracle.sol";
import {RolesAuthority, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import {TokenAllowlist, IAllowlist, ITokenBalance} from "src/periphery/TokenAllowlist.sol";
import {FixedStrikeOptionTeller, FixedStrikeOptionToken, FullMath} from "src/fixed-strike/FixedStrikeOptionTeller.sol";
import {MOLMFactory, OOLMFactory, ManualStrikeOLM, OracleStrikeOLM} from "src/fixed-strike/liquidity-mining/OLMFactory.sol";

contract FixedStrikeOLMTest is Test {
    using FullMath for uint256;

    address public guardian;
    address public alice;
    address public bob;
    address public carol;

    MockERC20 public abc;
    MockERC20 public def;
    MockERC20 public ghi;
    MockERC20 public jkl;
    MockERC20 public ve;

    RolesAuthority public auth;
    FixedStrikeOptionTeller public teller;
    MOLMFactory public molmFactory;
    OOLMFactory public oolmFactory;
    ManualStrikeOLM public molm;
    OracleStrikeOLM public oolm;
    MockBondOracle public oracle;
    TokenAllowlist public allowlist;

    bytes public constant ZERO_BYTES = bytes("");

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
        molmFactory = new MOLMFactory(teller);
        oolmFactory = new OOLMFactory(teller);

        // Deploy mock tokens
        abc = new MockERC20("ABC", "ABC", 18);
        def = new MockERC20("DEF", "DEF", 18);
        ghi = new MockERC20("GHI", "GHI", 18);
        jkl = new MockERC20("JKL", "JKL", 9); // TODO create with 9 decimals to test decimal setting and strike/payout values
        ve = new MockERC20("Vote Escrow", "VE", 18);

        // Deploy allowlist
        allowlist = new TokenAllowlist();

        // Set permissions
        auth.setRoleCapability(uint8(0), address(teller), teller.setProtocolFee.selector, true);
        auth.setRoleCapability(uint8(0), address(teller), teller.claimFees.selector, true);
        auth.setUserRole(guardian, uint8(0), true);

        // Set protocol fee for testing
        vm.prank(guardian);
        teller.setProtocolFee(uint48(500)); // 0.5% fee

        // Mint tokens to users for testing
        def.mint(alice, 1_000_000 * 1e18);

        abc.mint(bob, 100_000 * 1e18);
        ve.mint(bob, 100 * 1e18);

        abc.mint(carol, 100_000 * 1e18);
    }

    function _manualStrikeOLM() internal {
        // Create OLM
        vm.prank(alice);
        molm = molmFactory.deploy(abc, def);

        // Initialize OLM
        uint8 payoutDecimals = def.decimals();
        vm.prank(alice);
        molm.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(14 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day),
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Deposit payout tokens into OLM
        vm.prank(alice);
        def.transfer(address(molm), 1e6 * 10 ** payoutDecimals);

        // Have users approve OLM contract for the staked token
        vm.prank(bob);
        abc.approve(address(molm), type(uint256).max);

        vm.prank(carol);
        abc.approve(address(molm), type(uint256).max);
    }

    function _oracleStrikeOLM() internal {
        // Create mock oracle
        oracle = new MockBondOracle();

        // Configure oracle price and decimals for payout and quote token
        oracle.setPrice(ghi, def, 10e18);
        oracle.setDecimals(ghi, def, 18);

        // Create OLM
        vm.prank(alice);
        oolm = oolmFactory.deploy(abc, def);

        // Initialize OLM
        uint8 payoutDecimals = def.decimals();
        vm.prank(alice);
        oolm.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(14 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(
                oracle, // oracle address
                10e3, // 10% discount
                5e18 // min strike price
            ) // bytes calldata other_
        );

        // Deposit payout tokens into OLM
        vm.prank(alice);
        def.transfer(address(oolm), 1e6 * 10 ** payoutDecimals);

        // Have users approve OLM contract for the staked token
        vm.prank(bob);
        abc.approve(address(oolm), type(uint256).max);

        vm.prank(carol);
        abc.approve(address(oolm), type(uint256).max);
    }

    /* ========== MANUAL, FIXED STRIKE OLM TESTS ========== */
    //  DONE
    //  User actions
    //  [X] - stake
    //      [X] - new staker (no existing balance)
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - new epoch starts if applicable and user receives transition reward
    //          [X] - user balance is updated to the amount being staked
    //          [X] - total balance is updated to the existing balance plus the new amount
    //          [X] - contract receives amount of stakedTokens from user
    //      [X] - existing staker
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - new epoch starts if applicable and user receives transition reward
    //          [X] - user balance is updated to the existing balance plus the new amount
    //          [X] - total balance is updated to the existing balance plus the new amount
    //          [X] - contract receives amount of stakedTokens from user
    //          [X] - user receives outstanding rewards if applicable
    //      [X] - reverts if amount is zero
    //      [X] - reverts if not initialized
    //      [X] - staker must be on allowlist, if it is being used
    //  [X] - unstake
    //      [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //      [X] - new epoch starts if applicable and user receives transition reward
    //      [X] - reverts if user has a zero balance
    //      [X] - reverts if amount is greater than user balance
    //      [X] - reverts if amount is zero
    //      [X] - user receives outstanding rewards if applicable
    //      [X] - user balance is updated to the existing balance minus the amount
    //      [X] - total balance is updated to the existing balance minus the amount
    //      [X] - contract sends the amount of staked tokens to the user
    //  [X] - unstakeAll
    //      [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //      [X] - new epoch starts if applicable and user receives transition reward
    //      [X] - reverts if user has a zero balance
    //      [X] - user receives outstanding rewards if applicable
    //      [X] - user balance is updated to zero
    //      [X] - total balance is updated to the existing balance minus the amount
    //  [X] - emergencyUnstake
    //      [X] - reverts if user has a zero balance
    //      [X] - user receives outstanding rewards if applicable
    //      [X] - user balance is updated to zero
    //      [X] - total balance is updated to the existing balance minus the amount
    //  [X] - claimRewards
    //      [X] - reverts if user has a zero balance
    //      [X] - already claimed up to present (no rewards to claim)
    //          [X] - storedRewardsPerToken and lastRewardUpdate stay the same (no update because this means the user called twice in the same timestamp)
    //          [X] - new epoch doesn't start because this situation only happens when the user calls twice in the same timestamp
    //          [X] - user receives no rewards
    //          [X] - returns zero
    //      [X] - already claimed some for current epoch, but has new rewards to claim
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - new epoch doesn't start since this is within a given epoch duration
    //          [X] - user receives outstanding rewards from current epoch
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for current epoch, but has claimed previous epoch rewards
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from current epoch
    //          [X] - returns amount of rewards claimed
    //      [X] - rewards to claim from multiple epochs
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from current epoch and previous unclaimed epochs
    //          [X] - returns amount of rewards claimed
    //      [X] - rewards to claim from multiple epochs, but some are expired
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from current epoch and previous unclaimed epochs (excludes expired epochs)
    //          [X] - returns amount of rewards claimed (excludes expired epochs)
    //  [X] - claimNextEpochRewards
    //      [X] - reverts if user has a zero balance
    //      [X] - already claimed up to present (no rewards to claim)
    //          [X] - storedR ewardsPerToken and lastRewardUpdate stay the same (no update because this means the user called twice in the same timestamp)
    //          [X] - new epoch doesn't start because this situation only happens when the user calls twice in the same timestamp
    //          [X] - user receives no rewards
    //          [X] - user last claimed epoch is the same
    //          [X] - returns zero
    //      [X] - already claimed some for current epoch, but has new rewards to claim
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from current epoch
    //          [X] - user last claimed epoch is the same
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for current epoch, but has claimed previous epoch rewards
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from current epoch
    //          [X] - user last claimed epoch is updated to the current epoch
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for current epoch and part of previous epoch
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from the current epoch and previous epoch
    //          [X] - user last claimed epoch is updated to the current epoch
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for multiple epochs, but no remaining rewards on last claimed epoch
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards from the next unclaimed epoch
    //          [X] - user last claimed epoch is increased by 1
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for multiple epochs, and there are remaining rewards on last claimed epoch
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives outstanding rewards remaining from their last claimed epoch and the next unclaimed epoch
    //          [X] - user last claimed epoch is increased by 1
    //          [X] - returns amount of rewards claimed
    //      [X] - has not claimed rewards for multiple epochs, and the option for the next unclaimed epoch has expired
    //          [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //          [X] - user receives no rewards because the option has expired
    //          [X] - user last claimed epoch is increased by 1
    //          [X] - returns zero
    //
    //  Admin actions
    //  [X] - initialize
    //      [X] - reverts if already initialized
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if any parameters are invalid
    //          [X] - quoteToken is zero address or not a contract
    //          [X] - option eligible duration is less than minimum duration on teller
    //          [X] - option expires before the epoch duration is over
    //          [X] - receiver is zero address
    //          [X] - strike price is not zero
    //          [X] - allowlist is not zero AND not a contract
    //          [X] - allowlist registration fails
    //      [X] - when initialized
    //          [X] - all data set correctly
    //          [X] - initialized is true
    //          [X] - depositEnabled is true
    //  [X] - setDepositsEnabled
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - depositEnabled is updated
    //  [X] - triggerNextEpoch
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - can start a new epoch early
    //      [X] - can start a new epoch on time
    //      [X] - new epoch starts successfully
    //      [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //  [X] - withdrawPayoutTokens
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if amount is greater than the contract balance
    //      [X] - reverts if amount is zero to avoid zero transfers
    //      [X] - contract sends the amount of payout tokens to the provided address
    //  [X] - setRewardRate
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - storedRewardsPerToken and lastRewardUpdate are updated
    //      [X] - rewardRate is updated
    //  [X] - setEpochDuration
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if epoch duration is less than the configured option expiry
    //      [X] - epochDuration is updated
    //  [X] - setEpochTransitionReward
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - epochTransitionReward is updated
    //  [X] - setOptionReceiver
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - option receiver is updated
    //  [X] - setOptionDuration
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if option eligible duration is less than teller minimum
    //      [X] - reverts if option expires before epoch duration is over
    //      [X] - timeUntilEligible and eligibleDuration are updated
    //  [X] - setQuoteToken
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if quoteToken is zero address or not a contract
    //      [X] - quoteToken is updated
    //  [X] - setStrikePrice
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if strike price is zero
    //      [X] - strike price is updated
    //  [X] - setAllowlist
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if allowlist is not zero AND not a contract
    //      [X] - reverts if allowlist registration fails
    //      [X] - allowlist can be set to zero address (not used)
    //      [X] - allowlist can be set to valid contract
    //
    //  View functions
    //  [X] - currentRewardsPerToken
    //  [X] - nextStrikePrice

    /* ========== stake ========== */

    function testRevert_stake_zeroAmount() public {
        _manualStrikeOLM();

        // Try to stake zero amount, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidAmount()");
        vm.expectRevert(err);
        vm.prank(bob);
        molm.stake(0, ZERO_BYTES);
    }

    function testRevert_stake_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to stake, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(bob);
        olm_.stake(1e18, ZERO_BYTES);
    }

    function testFuzz_stake_newStaker(uint256 amount_) public {
        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        _manualStrikeOLM();

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 0);
        assertEq(startUserBalance, 0);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 0);

        // Stake tokens for bob, expect success
        // Don't expect rewards to be updated or a new epoch to start since
        // we are at the same timestamp as the contract was initialized at
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);
    }

    function testFuzz_stake_newStaker_rewardUpdate(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake an amount with another user so that rewards are accrued
        vm.prank(carol);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 1e18);
        assertEq(startUserBalance, 0);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 1e18);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Stake tokens for bob, expect success
        // Expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(1000e18 * 1e18) / 1e18
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + uint256(1000e18 * 1e18) / 1e18
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);
    }

    function testFuzz_stake_newStaker_newEpoch(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake an amount with another user so that rewards are accrued
        vm.prank(carol);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 1e18);
        assertEq(startUserBalance, 0);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 1e18);

        // Warp forward in time 7 days so a new epoch can be started
        vm.warp(block.timestamp + 7 days);

        // Stake tokens for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(7 * 1000e18 * 1e18) / 1e18
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + uint256(7 * 1000e18 * 1e18) / 1e18
        );
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch + 1);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);

        // Bob shouldn't get any staking rewards, but he should receive the epoch transition reward
        // Epoch 1 token = zero balance
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(optionToken.balanceOf(bob), uint256(0));
        // Epoch 2 token = 1e18
        optionToken = molm.epochOptionTokens(startEpoch + 1);
        assertEq(optionToken.balanceOf(bob), uint256(1e18));
    }

    function testFuzz_stake_existingStaker(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 1e18);
        assertEq(startUserBalance, 1e18);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 1e18);

        // Stake more tokens for bob, expect success
        // Don't expect rewards to be updated or a new epoch to start since
        // we are at the same timestamp as the contract was initialized at
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);
    }

    function testFuzz_stake_existingStaker_rewardUpdate(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 1e18);
        assertEq(startUserBalance, 1e18);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 1e18);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Stake more tokens for bob, expect success
        // Expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(1000e18) * 1e18) / 1e18
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(1000e18) * 1e18) / 1e18
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);

        // Bob should receive all the staking rewards from the first day since he was the only staker
        // These were claimed when adding to his stake
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(optionToken.balanceOf(bob), (uint256(1000e18) * 1e18) / 1e18);
    }

    function testFuzz_stake_existingStaker_newEpoch(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= abc.balanceOf(bob));

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, 1e18);
        assertEq(startUserBalance, 1e18);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, 1e18);

        // Warp forward in time 7 days so a new epoch can be started
        vm.warp(block.timestamp + 7 days);

        // Stake tokens for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.stake(amount_, ZERO_BYTES);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance + amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance + amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(7 * 1000e18 * 1e18) / 1e18
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + uint256(7 * 1000e18 * 1e18) / 1e18
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch + 1);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance + amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance - amount_);

        // Bob gets epoch 1 staking rewards and epoch 2 transition reward
        // Epoch 1 token = rewards claimed
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(optionToken.balanceOf(bob), uint256(7 * 1000e18 * 1e18) / 1e18);
        // Epoch 2 token = 1e18
        optionToken = molm.epochOptionTokens(startEpoch + 1);
        assertEq(optionToken.balanceOf(bob), uint256(1e18));
    }

    function test_stake_allowlist() public {
        // Deploy a new molm
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Initialize the new molm with an allowlist
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            carol, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            allowlist, // IAllowlist allowlist_
            abi.encode(ve, 10e18), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Approve the new olm from bob and carol for the staking token
        vm.prank(bob);
        abc.approve(address(olm_), type(uint256).max);

        vm.prank(carol);
        abc.approve(address(olm_), type(uint256).max);

        // In the setup, bob is eligible per the balance requirements of the ve token, but carol is not

        // Try to stake with bob, expect success
        vm.prank(bob);
        olm_.stake(1e18, ZERO_BYTES);

        // Try to stake with carol, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_NotAllowed()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.stake(1e18, ZERO_BYTES);
    }

    /* ========== unstake ========== */

    function testRevert_unstake_zeroAmount() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        // Try to unstake a zero amount, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidAmount()");
        vm.expectRevert(err);
        vm.prank(bob);
        molm.unstake(0);
    }

    function testRevert_unstake_zeroUserBalance(uint256 amount_) public {
        _manualStrikeOLM();

        vm.assume(amount_ <= abc.totalSupply());

        // Try to unstake with a zero balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_ZeroBalance()");
        vm.expectRevert(err);
        molm.unstake(amount_);
    }

    function testRevert_unstake_amountGreaterThanUserBalance(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        vm.assume(amount_ > abc.balanceOf(bob));

        // Try to unstake with an amount greater than the user balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidAmount()");
        vm.expectRevert(err);
        vm.prank(bob);
        molm.unstake(amount_);
    }

    function testFuzz_unstake(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= bobBalance);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Unstake tokens for bob, expect success
        // Don't expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.unstake(amount_);

        // Compare contract state after unstaking
        assertEq(molm.totalBalance(), startTotalBalance - amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance - amount_);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + amount_);
    }

    function testFuzz_unstake_rewardUpdate(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= bobBalance);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Unstake more tokens for bob, expect success
        // Expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.unstake(amount_);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance - amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance - amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(1000e18 * 1e18) / bobBalance)
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + amount_);

        // Bob should receive all the staking rewards from the first day since he was the only staker
        // These were claimed when adding to his stake
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(
            optionToken.balanceOf(bob),
            ((uint256(1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
    }

    function testFuzz_unstake_newEpoch(uint256 amount_) public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        vm.assume(amount_ > 0 && amount_ <= bobBalance);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 7 days so a new epoch can be started
        vm.warp(block.timestamp + 7 days);

        // Unstake tokens for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.unstake(amount_);

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance - amount_);
        assertEq(molm.stakeBalance(bob), startUserBalance - amount_);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(7 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(7 * 1000e18 * 1e18) / bobBalance)
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch + 1);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - amount_);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + amount_);

        // Bob gets epoch 1 staking rewards and epoch 2 transition reward
        // Epoch 1 token = rewards claimed
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(
            optionToken.balanceOf(bob),
            ((uint256(7 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        // Epoch 2 token = 1e18
        optionToken = molm.epochOptionTokens(startEpoch + 1);
        assertEq(optionToken.balanceOf(bob), uint256(1e18));
    }

    /* ========== unstakeAll ========== */

    function testRevert_unstakeAll_zeroUserBalance() public {
        _manualStrikeOLM();

        // Try to unstake with a zero balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_ZeroBalance()");
        vm.expectRevert(err);
        molm.unstakeAll();
    }

    function test_unstakeAll() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Unstake all tokens for bob, expect success
        // Don't expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.unstakeAll();

        // Compare contract state after unstaking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);
    }

    function test_unstakeAll_rewardUpdate() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Unstake all tokens for bob, expect success
        // Expect rewards to be updated
        // Don't expect a new epoch to start since we within the epoch duration of the first epoch still
        vm.prank(bob);
        molm.unstakeAll();

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(1000e18 * 1e18) / bobBalance)
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);

        // Bob should receive all the staking rewards from the first day since he was the only staker
        // These were claimed when adding to his stake
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(
            optionToken.balanceOf(bob),
            ((uint256(1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
    }

    function test_unstakeAll_newEpoch() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 7 days so a new epoch can be started
        vm.warp(block.timestamp + 7 days);

        // Unstake all tokens for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.unstakeAll();

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(7 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(7 * 1000e18 * 1e18) / bobBalance)
        ); // amount is the rewards per day in payout tokens * 10 ** stakedTokenDecimals because the total balance starts at 1
        assertEq(molm.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(molm.epoch(), startEpoch + 1);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);

        // Bob gets epoch 1 staking rewards and epoch 2 transition reward
        // Epoch 1 token = rewards claimed
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(
            optionToken.balanceOf(bob),
            ((uint256(7 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        // Epoch 2 token = 1e18
        optionToken = molm.epochOptionTokens(startEpoch + 1);
        assertEq(optionToken.balanceOf(bob), uint256(1e18));
    }

    /* ========== emergencyUnstakeAll =========== */
    function testRevert_emergencyUnstakeAll_zeroUserBalance() public {
        _manualStrikeOLM();

        // Try to unstake with a zero balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_ZeroBalance()");
        vm.expectRevert(err);
        molm.emergencyUnstakeAll();
    }

    function test_emergencyUnstakeAll() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Unstake all tokens for bob, expect success
        // Don't expect rewards to be updated
        // Don't expect a new epoch to start
        vm.prank(bob);
        molm.unstakeAll();

        // Compare contract state after unstaking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);
    }

    function test_emergencyUnstakeAll_noRewardUpdate() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Emergency unstake all tokens for bob, expect success
        // Don't expect rewards to be updated
        // Don't expect a new epoch to start
        vm.prank(bob);
        molm.emergencyUnstakeAll();

        // Compare contract state after staking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);

        // Bob shouldn't receive any staking rewards even though he has earned them since this is an emergency withdraw
        // Rewards are lost on emergency unstake
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(optionToken.balanceOf(bob), 0);
    }

    function test_emergencyUnstakeAll_noNewEpoch() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Get initial contract state
        uint256 startTotalBalance = molm.totalBalance();
        uint256 startUserBalance = molm.stakeBalance(bob);
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startContractTokenBalance = abc.balanceOf(address(molm));
        uint256 startUserTokenBalance = abc.balanceOf(bob);

        assertEq(startTotalBalance, bobBalance);
        assertEq(startUserBalance, bobBalance);
        assertEq(startStoredRewardsPerToken, 0);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp));
        assertEq(startEpoch, 1);
        assertEq(startContractTokenBalance, bobBalance);

        // Warp forward in time 7 days so a new epoch can be started
        vm.warp(block.timestamp + 7 days);

        // Emergency unstake all tokens for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.emergencyUnstakeAll();

        // Compare contract state after emergency unstaking
        assertEq(molm.totalBalance(), startTotalBalance - bobBalance);
        assertEq(molm.stakeBalance(bob), 0);
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(abc.balanceOf(address(molm)), startContractTokenBalance - bobBalance);
        assertEq(abc.balanceOf(bob), startUserTokenBalance + bobBalance);

        // Bob shouldn't receive any reward tokens or transition rewards since this is an emergency unstake
        // Epoch 1 token
        FixedStrikeOptionToken optionToken = molm.epochOptionTokens(startEpoch);
        assertEq(optionToken.balanceOf(bob), 0);
        // Epoch 2 token shouldn't exist yet
        optionToken = molm.epochOptionTokens(startEpoch + 1);
        assertEq(address(optionToken), address(0));
    }

    /* ========== claimRewards ========== */

    function testRevert_claimRewards_zeroUserBalance() public {
        _manualStrikeOLM();

        // Try to unstake with a zero balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_ZeroBalance()");
        vm.expectRevert(err);
        molm.claimRewards();
    }

    function test_claimRewards_alreadyClaimedAll() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim rewards for bob, expect success
        // Expect rewards to be updated
        // Expect no new epoch to start
        vm.prank(bob);
        molm.claimRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startRewardBalance = molm.epochOptionTokens(1).balanceOf(bob);

        // Claim again when all rewards have been claimed already, expect no changes
        vm.prank(bob);
        uint256 rewards = molm.claimRewards();

        // Compare contract state after claiming rewards
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startRewardBalance);
        assertEq(rewards, 0);
    }

    function test_claimRewards_alreadyClaimedSome() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim rewards for bob, expect success
        // Expect rewards to be updated
        // Expect no new epoch to start
        vm.prank(bob);
        molm.claimRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startRewardBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startEpoch, 1);
        assertEq(startLastEpochClaimed, 1);
        assertEq(startRewardBalance, ((uint256(1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);

        // Warp forward another two days
        vm.warp(block.timestamp + 2 days);

        // Claim again, new rewards should be available for this epoch
        vm.prank(bob);
        uint256 rewards = molm.claimRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startRewardBalance + rewards);
        assertEq(rewards, ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), startLastEpochClaimed);
    }

    function test_claimRewards_upToCurrent() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 7 days (epoch duration)
        vm.warp(block.timestamp + 7 days);

        // Claim rewards for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.claimRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startEpoch, 2);
        assertEq(startLastEpochClaimed, 1);
        assertEq(
            startFirstBalance,
            ((uint256(7 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(startSecondBalance, 1e18); // epoch transition reward

        // Warp forward another two days
        vm.warp(block.timestamp + 2 days);

        // Claim again, rewards should be for second epoch only
        vm.prank(bob);
        uint256 rewards = molm.claimRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startFirstBalance);
        assertEq(molm.epochOptionTokens(2).balanceOf(bob), startSecondBalance + rewards);
        assertEq(rewards, ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 2);
    }

    function test_claimRewards_multipleEpochs() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 5 days
        vm.warp(block.timestamp + 5 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 1 -> 2
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward in time another 5 days
        vm.warp(block.timestamp + 5 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 2 -> 3
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward another 2 days to have rewards from current epoch
        vm.warp(block.timestamp + 2 days);

        // Get contract state (should be as of start of 3rd epoch)
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint256 startThirdBalance = molm.epochOptionTokens(3).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startStoredRewardsPerToken, uint256(10 * 1000e18 * 1e18) / bobBalance);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp - 2 days));
        assertEq(startEpoch, 3);
        assertEq(startLastEpochClaimed, 0);
        assertEq(startFirstBalance, 0);
        assertEq(startSecondBalance, 0);
        assertEq(startThirdBalance, 0);

        // Claim rewards, expect rewards for first, second, and third epochs
        // First epoch 5 days of 1000e18 rewards per day
        // Second epoch 5 days of 1000e18 rewards per day
        // Third epoch 2 days of 1000e18 rewards per day
        vm.prank(bob);
        uint256 rewards = molm.claimRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(12 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(
            molm.epochOptionTokens(1).balanceOf(bob),
            startFirstBalance + ((uint256(5 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(
            molm.epochOptionTokens(2).balanceOf(bob),
            startSecondBalance + ((uint256(5 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(
            molm.epochOptionTokens(3).balanceOf(bob),
            startThirdBalance + ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(rewards, ((uint256(12 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 3);
    }

    function test_claimRewards_multipleEpochs_someExpired() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 7 days (epoch duration)
        vm.warp(block.timestamp + 7 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 1 -> 2
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward in time another 7 days (epoch duration)
        vm.warp(block.timestamp + 7 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 2 -> 3
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward another 2 days to have rewards from current epoch
        vm.warp(block.timestamp + 2 days);

        // Get contract state (should be as of start of 3rd epoch)
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint256 startThirdBalance = molm.epochOptionTokens(3).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startStoredRewardsPerToken, uint256(14 * 1000e18 * 1e18) / bobBalance);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp - 2 days));
        assertEq(startEpoch, 3);
        assertEq(startLastEpochClaimed, 0);
        assertEq(startFirstBalance, 0);
        assertEq(startSecondBalance, 0);
        assertEq(startThirdBalance, 0);

        // Claim rewards, expect rewards for first, second, and third epochs
        // First epoch 7 days of 1000e18 rewards per day -> these tokens are expired so shouldn't receive any
        // Second epoch 7 days of 1000e18 rewards per day
        // Third epoch 2 days of 1000e18 rewards per day
        vm.prank(bob);
        uint256 rewards = molm.claimRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(16 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startFirstBalance); // first option expired
        assertEq(
            molm.epochOptionTokens(2).balanceOf(bob),
            startSecondBalance + ((uint256(7 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(
            molm.epochOptionTokens(3).balanceOf(bob),
            startThirdBalance + ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(rewards, ((uint256(9 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 3);
    }

    /* ========== claimNextEpochRewards ========== */

    function testRevert_claimNextEpochRewards_zeroUserBalance() public {
        _manualStrikeOLM();

        // Try to unstake with a zero balance, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_ZeroBalance()");
        vm.expectRevert(err);
        molm.claimNextEpochRewards();
    }

    function test_claimNextEpochRewards_alreadyClaimedAll() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim next epoch rewards for bob, expect success
        // Expect rewards to be updated
        // Expect no new epoch to start
        vm.prank(bob);
        molm.claimNextEpochRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startRewardBalance = molm.epochOptionTokens(1).balanceOf(bob);

        // Try to claim next epoch rewards when all rewards have been claimed already, expect no changes
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(molm.rewardsPerTokenStored(), startStoredRewardsPerToken);
        assertEq(molm.rewardsPerTokenClaimed(bob), startUserRewardsPerTokenClaimed);
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate);
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startRewardBalance);
        assertEq(rewards, 0);
    }

    function test_claimNextEpochRewards_alreadyClaimedSome() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim rewards for bob, expect success
        // Expect rewards to be updated
        // Expect no new epoch to start
        vm.prank(bob);
        molm.claimNextEpochRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startRewardBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startEpoch, 1);
        assertEq(startLastEpochClaimed, 1);
        assertEq(startRewardBalance, ((uint256(1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);

        // Warp forward another two days
        vm.warp(block.timestamp + 2 days);

        // Claim again, new rewards should be available for this epoch
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startRewardBalance + rewards);
        assertEq(rewards, ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), startLastEpochClaimed);
    }

    function test_claimNextEpochRewards_upToCurrent() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 7 days (epoch duration)
        vm.warp(block.timestamp + 7 days);

        // Claim rewards for bob, expect success
        // Expect rewards to be updated
        // Expect new epoch to start
        vm.prank(bob);
        molm.claimNextEpochRewards();

        // Get contract state
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startEpoch, 2);
        assertEq(startLastEpochClaimed, 1);
        assertEq(
            startFirstBalance,
            ((uint256(7 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(startSecondBalance, 1e18); // epoch transition reward

        // Warp forward another two days
        vm.warp(block.timestamp + 2 days);

        // Claim again, rewards should be for second epoch only
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startFirstBalance);
        assertEq(molm.epochOptionTokens(2).balanceOf(bob), startSecondBalance + rewards);
        assertEq(rewards, ((uint256(2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 2);
    }

    function test_claimNextEpochRewards_multipleEpochsUnclaimed_noPrevious() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 5 days
        vm.warp(block.timestamp + 5 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 1 -> 2
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward in time another 5 days
        vm.warp(block.timestamp + 5 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 2 -> 3
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward another 2 days to have rewards from current epoch
        vm.warp(block.timestamp + 2 days);

        // Get contract state (should be as of start of 3rd epoch)
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint256 startThirdBalance = molm.epochOptionTokens(3).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startStoredRewardsPerToken, uint256(10 * 1000e18 * 1e18) / bobBalance);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp - 2 days));
        assertEq(startEpoch, 3);
        assertEq(startLastEpochClaimed, 0);
        assertEq(startFirstBalance, 0);
        assertEq(startSecondBalance, 0);
        assertEq(startThirdBalance, 0);

        // Claim next epoch rewards, expect rewards for first epoch only since no rewards have been claimed
        // First epoch 5 days of 1000e18 rewards per day
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(5 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(
            molm.epochOptionTokens(1).balanceOf(bob),
            startFirstBalance + ((uint256(5 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(molm.epochOptionTokens(2).balanceOf(bob), startSecondBalance);
        assertEq(molm.epochOptionTokens(3).balanceOf(bob), startThirdBalance);
        assertEq(rewards, ((uint256(5 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 1);
    }

    function test_claimNextEpochRewards_multipleEpochsUnclaimed_somePrevious() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 2 days
        vm.warp(block.timestamp + 2 days);

        // Claim some rewards from epoch 1
        vm.prank(bob);
        molm.claimNextEpochRewards();

        // Warp forward in time another 3 days
        vm.warp(block.timestamp + 3 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 1 -> 2
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward in time another 5 days
        vm.warp(block.timestamp + 5 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 2 -> 3
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward another 2 days to have rewards from current epoch
        vm.warp(block.timestamp + 2 days);

        // Get contract state (should be as of start of 3rd epoch)
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint256 startThirdBalance = molm.epochOptionTokens(3).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startStoredRewardsPerToken, uint256(10 * 1000e18 * 1e18) / bobBalance);
        assertEq(startUserRewardsPerTokenClaimed, uint256(2 * 1000e18 * 1e18) / bobBalance);
        assertEq(startLastRewardUpdate, uint48(block.timestamp - 2 days));
        assertEq(startEpoch, 3);
        assertEq(startLastEpochClaimed, 1);
        assertEq(
            startFirstBalance,
            (uint256((2 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(startSecondBalance, 0);
        assertEq(startThirdBalance, 0);

        // Claim next epoch rewards, expect rewards for first epoch and second epoch since only partial rewards have been claimed for the first epoch
        // First epoch 5 days of 1000e18 rewards per day (have already claimed 2 days)
        // First epoch 5 days of 1000e18 rewards per day
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(8 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(
            molm.epochOptionTokens(1).balanceOf(bob),
            startFirstBalance + ((uint256(3 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(
            molm.epochOptionTokens(2).balanceOf(bob),
            startSecondBalance + ((uint256(5 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18
        );
        assertEq(molm.epochOptionTokens(3).balanceOf(bob), startThirdBalance);
        assertEq(rewards, ((uint256(8 * 1000e18 * 1e18) / bobBalance) * bobBalance) / 1e18);
        assertEq(molm.lastEpochClaimed(bob), 2);
    }

    function test_claimNextEpochRewards_multipleEpochsUnclaimed_nextExpired() public {
        _manualStrikeOLM();

        // Stake initial tokens for bob
        uint256 bobBalance = abc.balanceOf(bob);
        vm.prank(bob);
        molm.stake(bobBalance, ZERO_BYTES);

        // Warp forward in time 7 days
        vm.warp(block.timestamp + 7 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 1 -> 2
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward in time another 7 days
        vm.warp(block.timestamp + 7 days);

        // Manually trigger epoch transition (can also be done via other user actions)
        // Epoch 2 -> 3
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Warp forward another 2 days to have rewards from current epoch
        vm.warp(block.timestamp + 2 days);

        // Get contract state (should be as of start of 3rd epoch)
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint256 startUserRewardsPerTokenClaimed = molm.rewardsPerTokenClaimed(bob);
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();
        uint48 startEpoch = molm.epoch();
        uint256 startFirstBalance = molm.epochOptionTokens(1).balanceOf(bob);
        uint256 startSecondBalance = molm.epochOptionTokens(2).balanceOf(bob);
        uint256 startThirdBalance = molm.epochOptionTokens(3).balanceOf(bob);
        uint48 startLastEpochClaimed = molm.lastEpochClaimed(bob);

        assertEq(startStoredRewardsPerToken, uint256(14 * 1000e18 * 1e18) / bobBalance);
        assertEq(startUserRewardsPerTokenClaimed, 0);
        assertEq(startLastRewardUpdate, uint48(block.timestamp - 2 days));
        assertEq(startEpoch, 3);
        assertEq(startLastEpochClaimed, 0);
        assertEq(startFirstBalance, 0);
        assertEq(startSecondBalance, 0);
        assertEq(startThirdBalance, 0);

        // Claim next epoch rewards, expect rewards for first epoch only since no rewards have been claimed
        // First epoch 5 days of 1000e18 rewards per day -> these should be expired
        vm.prank(bob);
        uint256 rewards = molm.claimNextEpochRewards();

        // Compare contract state after claiming rewards
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + (uint256(2 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(
            molm.rewardsPerTokenClaimed(bob),
            startUserRewardsPerTokenClaimed + (uint256(7 * 1000e18 * 1e18) / bobBalance)
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(2 days));
        assertEq(molm.epoch(), startEpoch);
        assertEq(molm.epochOptionTokens(1).balanceOf(bob), startFirstBalance);
        assertEq(molm.epochOptionTokens(2).balanceOf(bob), startSecondBalance);
        assertEq(molm.epochOptionTokens(3).balanceOf(bob), startThirdBalance);
        assertEq(rewards, 0);
        assertEq(molm.lastEpochClaimed(bob), 1);
    }

    /* ========== initialize ========== */

    function testRevert_initialize_alreadyInitialized() public {
        _manualStrikeOLM();

        // Setup initializes the contract so we shouldn't be able to initialize again
        uint8 payoutDecimals = def.decimals();
        bytes memory err = abi.encodeWithSignature("OLM_AlreadyInitialized()");
        vm.expectRevert(err);
        vm.prank(alice);
        molm.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );
    }

    function testRevert_initialize_notOwner(address other_) public {
        vm.assume(other_ != carol);

        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Try to initialize the new molm with a different address, expect revert
        uint8 payoutDecimals = def.decimals();
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Verify that the new molm is not initialized
        assertFalse(olm_.initialized());

        // Try to initialize the new molm with the correct address, expect success
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Verify that the new molm is initialized
        assertTrue(olm_.initialized());
    }

    function testRevert_initialize_invalidParameters() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Try to initialize the new molm with invalid parameters, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        uint8 payoutDecimals = def.decimals();

        // Case 1: Quote Token is zero address
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ERC20(address(0)), // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 2: Quote token is not a contract
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ERC20(bob), // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 3: Eligible duration is less than the teller minimum
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(7 days), // uint48 timeUntilEligible_
            uint48(1 days) - 1, // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 4: Option expires before epoch is over
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(5 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 5: Receiver is zero address
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            address(0), // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 6: Strike price is zero
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(0) // bytes calldata other_ (strike price in this case)
        );

        // Case 7: Allowlist is non-zero, but doesn't conform to interface
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(bob), // IAllowlist allowlist_
            abi.encode(ve, 10e18), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Case 7: Token provided to allowlist doesn't conform to ITokenBalance
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            allowlist, // IAllowlist allowlist_
            abi.encode(bob, 10e18), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );
    }

    function testFuzz_initialize_durations(
        uint48 timeUntilEligible_,
        uint48 eligibleDuration_,
        uint48 epochDuration_
    ) public {
        if (
            eligibleDuration_ > uint48(365 days) ||
            timeUntilEligible_ > uint48(365 days) ||
            epochDuration_ > uint48(365 days)
        ) return;

        vm.assume(
            eligibleDuration_ >= uint48(1 days) &&
                epochDuration_ <= timeUntilEligible_ + eligibleDuration_ - uint48(1 days)
        );

        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Try to initialize the new molm with fuzzed parameters, expect success
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            timeUntilEligible_, // uint48 timeUntilEligible_
            eligibleDuration_, // uint48 eligibleDuration_
            carol, // address receiver_
            epochDuration_, // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );
    }

    function test_initialize() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized and deposits are not enabled
        assertFalse(olm_.initialized());
        assertFalse(olm_.depositsEnabled());

        // Initialize the new molm
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            carol, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Verify that the molm is initialized
        assertTrue(olm_.initialized());

        // Check that all data was set correctly
        assertEq(address(olm_.quoteToken()), address(ghi));
        assertEq(olm_.timeUntilEligible(), uint48(1 days));
        assertEq(olm_.eligibleDuration(), uint48(7 days));
        assertEq(olm_.receiver(), carol);
        assertEq(olm_.epochDuration(), uint48(7 days));
        assertEq(olm_.epochTransitionReward(), 1 * 10 ** payoutDecimals);
        assertEq(olm_.rewardRate(), 1000 * 10 ** payoutDecimals);
        assertEq(olm_.strikePrice(), 5 * 1e18);
        assertEq(address(olm_.allowlist()), address(0));

        // Check that deposits are enabled and the first epoch was started
        assertTrue(olm_.depositsEnabled());
        assertEq(olm_.epoch(), uint48(1));
        assertEq(olm_.epochStart(), uint48(block.timestamp));
        assertEq(olm_.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(olm_.totalBalance(), 0);

        // Check that the option token created for the first epoch was set correctly
        FixedStrikeOptionToken optionToken = olm_.epochOptionTokens(1);
        assertEq(address(optionToken.payout()), address(def));
        assertEq(address(optionToken.quote()), address(ghi));
        assertEq(optionToken.eligible(), uint48(block.timestamp) + uint48(1 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.expiry(), uint48(block.timestamp) + uint48(8 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.receiver(), carol);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), 5 * 1e18);
    }

    function test_initialize_allowlist() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized and deposits are not enabled
        assertFalse(olm_.initialized());
        assertFalse(olm_.depositsEnabled());

        // Initialize the new molm
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            carol, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            allowlist, // IAllowlist allowlist_
            abi.encode(ve, 10e18), // bytes calldata allowlistParams_
            abi.encode(5 * 1e18) // bytes calldata other_ (strike price in this case)
        );

        // Verify that the molm is initialized
        assertTrue(olm_.initialized());

        // Check that all data was set correctly
        assertEq(address(olm_.quoteToken()), address(ghi));
        assertEq(olm_.timeUntilEligible(), uint48(1 days));
        assertEq(olm_.eligibleDuration(), uint48(7 days));
        assertEq(olm_.receiver(), carol);
        assertEq(olm_.epochDuration(), uint48(7 days));
        assertEq(olm_.epochTransitionReward(), 1 * 10 ** payoutDecimals);
        assertEq(olm_.rewardRate(), 1000 * 10 ** payoutDecimals);
        assertEq(olm_.strikePrice(), 5 * 1e18);
        assertEq(address(olm_.allowlist()), address(allowlist));

        // Check that contract is configured correctly on the allowlist
        (ITokenBalance token, uint96 threshold) = allowlist.checks(address(olm_));
        assertEq(address(token), address(ve));
        assertEq(threshold, uint96(10e18));
        vm.prank(address(olm_));
        bool allowed = allowlist.isAllowed(bob, ZERO_BYTES);
        assertTrue(allowed);
        vm.prank(address(olm_));
        allowed = allowlist.isAllowed(carol, ZERO_BYTES);
        assertFalse(allowed);

        // Check that deposits are enabled and the first epoch was started
        assertTrue(olm_.depositsEnabled());
        assertEq(olm_.epoch(), uint48(1));
        assertEq(olm_.epochStart(), uint48(block.timestamp));
        assertEq(olm_.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(olm_.totalBalance(), 0);

        // Check that the option token created for the first epoch was set correctly
        FixedStrikeOptionToken optionToken = olm_.epochOptionTokens(1);
        assertEq(address(optionToken.payout()), address(def));
        assertEq(address(optionToken.quote()), address(ghi));
        assertEq(optionToken.eligible(), uint48(block.timestamp) + uint48(1 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.expiry(), uint48(block.timestamp) + uint48(8 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.receiver(), carol);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), 5 * 1e18);
    }

    /* ========== setDepositsEnabled ========== */

    function testRevert_setDepositsEnabled_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Confirm that deposits are enabled on the molm
        assertTrue(molm.depositsEnabled());

        // Try to disable deposits as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setDepositsEnabled(false);

        // Confirm that deposits are still enabled on the molm
        assertTrue(molm.depositsEnabled());

        // Try to disable deposits as owner, expect success
        vm.prank(alice);
        molm.setDepositsEnabled(false);

        // Confirm that deposits are disabled on the molm
        assertFalse(molm.depositsEnabled());
    }

    function testRevert_setDepositsEnabled_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized and deposits are not enabled
        assertFalse(olm_.initialized());
        assertFalse(olm_.depositsEnabled());

        // Try to enable deposits as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setDepositsEnabled(true);

        // Confirm that deposits are still disabled on the molm
        assertFalse(olm_.depositsEnabled());
    }

    function test_setDepositsEnabled() public {
        _manualStrikeOLM();

        // Confirm that deposits are enabled on the molm
        assertTrue(molm.depositsEnabled());

        // Disable deposits as owner
        vm.prank(alice);
        molm.setDepositsEnabled(false);

        // Confirm that deposits are disabled on the molm
        assertFalse(molm.depositsEnabled());

        // Enable deposits as owner
        vm.prank(alice);
        molm.setDepositsEnabled(true);

        // Confirm that deposits are enabled on the molm
        assertTrue(molm.depositsEnabled());
    }

    /* ========== triggerNextEpoch ========== */

    function testRevert_triggerNextEpoch_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Confirm that it is currently the first epoch
        assertEq(molm.epoch(), uint48(1));

        // Try to trigger next epoch as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.triggerNextEpoch();

        // Confirm that it is still the first epoch
        assertEq(molm.epoch(), uint48(1));

        // Try to triggerNextEpoch as owner, expect success
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Confirm that it is now the second epoch
        assertEq(molm.epoch(), uint48(2));
    }

    function testRevert_triggerNextEpoch_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized and the first epoch has not started
        assertFalse(olm_.initialized());
        assertEq(olm_.epoch(), uint48(0));

        // Try to triggerNextEpoch as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.triggerNextEpoch();

        // Confirm that a new epoch did not start
        assertEq(olm_.epoch(), uint48(0));
    }

    function test_triggerNextEpoch_early() public {
        _manualStrikeOLM();

        // Stake some tokens on the OLM so that rewards accrue
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        // Confirm that it is currently the first epoch
        assertEq(molm.epoch(), uint48(1));

        // Warp forward 1 day so there are rewards to update
        vm.warp(block.timestamp + 1 days);

        // Cache the starting reward values
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();

        // Trigger next epoch as owner early (prior to epoch duration passing), expect success
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Confirm that it is now the second epoch
        assertEq(molm.epoch(), uint48(2));

        // Confirm that rewards were updated
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(1000e18 * 1e18) / 1e18
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(1 days));
    }

    function test_triggerNextEpoch_onTime() public {
        _manualStrikeOLM();

        // Stake some tokens on the OLM so that rewards accrue
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        // Confirm that it is currently the first epoch
        assertEq(molm.epoch(), uint48(1));

        // Warp forward 7 day so there are rewards to update and epoch duration is passed
        vm.warp(block.timestamp + 7 days);

        // Cache the starting reward values
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();

        // Trigger next epoch as owner on time (after epoch duration passing), expect success
        vm.prank(alice);
        molm.triggerNextEpoch();

        // Confirm that it is now the second epoch
        assertEq(molm.epoch(), uint48(2));

        // Confirm that rewards were updated
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(7 * 1000e18 * 1e18) / 1e18
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(7 days));
    }

    /* ========== withdrawPayoutTokens ========== */

    function testRevert_withdrawPayoutTokens_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache balance of payout tokens in the molm
        uint256 startBalance = def.balanceOf(address(molm));

        // Try to set epoch duration as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.withdrawPayoutTokens(other_, startBalance);

        // Confirm that the balance has not changed
        assertEq(def.balanceOf(address(molm)), startBalance);

        // Try to withdraw some payout tokens as owner, expect success
        vm.prank(alice);
        molm.withdrawPayoutTokens(bob, startBalance / 2);

        // Confirm that tokens were withdrawn
        assertEq(def.balanceOf(address(molm)), startBalance / 2);
    }

    function test_withdrawPayoutTokens_preInitialize() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Deposit some payout tokens to the new OLM
        def.mint(address(olm_), 1000e18);

        // Try to withdraw payout tokens as owner, expect success
        vm.prank(carol);
        olm_.withdrawPayoutTokens(carol, 500e18);

        // Confirm that the balance has decreased
        assertEq(def.balanceOf(address(olm_)), 500e18);
    }

    function testFuzz_withdrawPayoutTokens(uint256 amount_) public {
        _manualStrikeOLM();

        // Cache balance of payout tokens in the molm
        uint256 startBalance = def.balanceOf(address(molm));

        // If amount is greater than the balance or zero, expect revert
        // Otherwise, expect success
        if (amount_ > startBalance || amount_ == 0) {
            bytes memory err = abi.encodeWithSignature("OLM_InvalidAmount()");
            vm.expectRevert(err);
            vm.prank(alice);
            molm.withdrawPayoutTokens(bob, amount_);
        } else {
            vm.prank(alice);
            molm.withdrawPayoutTokens(bob, amount_);

            assertEq(def.balanceOf(address(molm)), startBalance - amount_);
            assertEq(def.balanceOf(bob), amount_);
        }
    }

    /* ========== setRewardRate ========== */

    function testRevert_setRewardRate_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial reward rate
        uint256 startRewardRate = molm.rewardRate();

        // Try to set reward rate as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setRewardRate(startRewardRate * 10);

        // Confirm that reward rate was not updated
        assertEq(molm.rewardRate(), startRewardRate);

        // Try to set reward rate as owner, expect success
        vm.prank(alice);
        molm.setRewardRate(startRewardRate / 2);

        // Confirm that reward rate was updated
        assertEq(molm.rewardRate(), startRewardRate / 2);
    }

    function testRevert_setRewardRate_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set reward rate as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setRewardRate(10e18);

        // Confirm that reward rate has not been set since the contract isn't initialized
        assertEq(olm_.rewardRate(), 0);
    }

    function test_setRewardRate() public {
        _manualStrikeOLM();

        // Stake some initial tokens so rewards accrue
        vm.prank(bob);
        molm.stake(1e18, ZERO_BYTES);

        // Cache initial reward rate
        uint256 startRewardRate = molm.rewardRate();

        // Warp forward 1 day so there are rewards to update
        vm.warp(block.timestamp + 1 days);

        // Cache the starting reward values
        uint256 startStoredRewardsPerToken = molm.rewardsPerTokenStored();
        uint48 startLastRewardUpdate = molm.lastRewardUpdate();

        // Try to set reward rate as owner, expect success
        vm.prank(alice);
        molm.setRewardRate(startRewardRate * 10);

        // Confirm that reward rate was updated
        assertEq(molm.rewardRate(), startRewardRate * 10);

        // Confirm that rewards were updated
        assertEq(
            molm.rewardsPerTokenStored(),
            startStoredRewardsPerToken + uint256(1000e18 * 1e18) / 1e18
        );
        assertEq(molm.lastRewardUpdate(), startLastRewardUpdate + uint48(1 days));
    }

    /* ========== setEpochDuration ========== */

    function testRevert_setEpochDuration_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial epoch duration
        uint48 startEpochDuration = molm.epochDuration();

        // Try to set epoch duration as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setEpochDuration(startEpochDuration - uint48(1 days));

        // Confirm that epoch duration was not updated
        assertEq(molm.epochDuration(), startEpochDuration);

        // Try to set epoch duration as owner, expect success
        vm.prank(alice);
        molm.setEpochDuration(startEpochDuration - uint48(2 days));

        // Confirm that epoch duration was updated
        assertEq(molm.epochDuration(), startEpochDuration - uint48(2 days));
    }

    function testRevert_setEpochDuration_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set epoch duration as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setEpochDuration(uint48(3 days));

        // Confirm that epoch duration has not been set since the contract isn't initialized
        assertEq(olm_.epochDuration(), 0);
    }

    function testFuzz_setEpochDuration(uint48 epochDuration_) public {
        _manualStrikeOLM();
        if (epochDuration_ > molm.timeUntilEligible() + molm.eligibleDuration()) {
            // Except revert since param is invalid
            bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
            vm.expectRevert(err);
            vm.prank(alice);
            molm.setEpochDuration(epochDuration_);
        } else {
            // Confirm that epoch duration was updated
            vm.prank(alice);
            molm.setEpochDuration(epochDuration_);
            assertEq(molm.epochDuration(), epochDuration_);
        }
    }

    /* ========== setEpochTransitionReward ========== */
    function testRevert_setEpochTransitionReward_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial epoch duration
        uint256 startEpochTransitionReward = molm.epochTransitionReward();

        // Try to set epoch transition reward as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setEpochTransitionReward(0);

        // Confirm that epoch transition reward was not updated
        assertEq(molm.epochTransitionReward(), startEpochTransitionReward);

        // Try to set epoch transition reward as owner, expect success
        vm.prank(alice);
        molm.setEpochTransitionReward(10e18);

        // Confirm that epoch transition reward was updated
        assertEq(molm.epochTransitionReward(), 10e18);
    }

    function testRevert_setEpochTransitionReward_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set epoch transition reward as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setEpochTransitionReward(10e18);

        // Confirm that epoch transition reward has not been set since the contract isn't initialized
        assertEq(olm_.epochTransitionReward(), 0);
    }

    function test_setEpochTransitionReward() public {
        _manualStrikeOLM();

        // Confirm that epoch transition reward is initialized to 1e18
        assertEq(molm.epochTransitionReward(), 1e18);

        // Update epoch transition reward as owner
        vm.prank(alice);
        molm.setEpochTransitionReward(10e18);

        // Confirm that epoch transition reward was updated
        assertEq(molm.epochTransitionReward(), 10e18);
    }

    /* ========== setOptionReceiver ========== */

    function testRevert_setOptionReceiver_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Try to set receiver as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setOptionReceiver(other_);

        // Confirm that receiver was not updated
        assertEq(molm.receiver(), alice);

        // Try to set receiver as owner, expect success
        vm.prank(alice);
        molm.setOptionReceiver(bob);

        // Confirm that receiver was updated
        assertEq(molm.receiver(), bob);
    }

    function testRevert_setOptionReceiver_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set receiver as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setOptionReceiver(carol);

        // Confirm that receiver has not been set since the contract isn't initialized
        assertEq(olm_.receiver(), address(0));
    }

    function test_setOptionReceiver() public {
        _manualStrikeOLM();

        // Confirm that receiver was set to alice
        assertEq(molm.receiver(), alice);

        // Try to set receiver as owner, expect success
        vm.prank(alice);
        molm.setOptionReceiver(bob);

        // Confirm that receiver was updated
        assertEq(molm.receiver(), bob);
    }

    /* ========== setOptionDuration ========== */

    function testRevert_setOptionDuration_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial time until eligible and eligible duration
        uint48 startEligibleDuration = molm.eligibleDuration();
        uint48 startTimeUntilEligible = molm.timeUntilEligible();

        // Try to set option duration as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setOptionDuration(uint48(3 days), uint48(5 days));

        // Confirm that option duration was not updated
        assertEq(molm.eligibleDuration(), startEligibleDuration);
        assertEq(molm.timeUntilEligible(), startTimeUntilEligible);

        // Try to set option duration as owner, expect success
        vm.prank(alice);
        molm.setOptionDuration(uint48(2 days), uint48(10 days));

        // Confirm that option duration was updated
        assertEq(molm.timeUntilEligible(), uint48(2 days));
        assertEq(molm.eligibleDuration(), uint48(10 days));
    }

    function testRevert_setOptionDuration_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set option duration as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setOptionDuration(uint48(5 days), uint48(5 days));

        // Confirm that option duration has not been set since the contract isn't initialized
        assertEq(olm_.eligibleDuration(), uint48(0));
        assertEq(olm_.timeUntilEligible(), uint48(0));
    }

    function testFuzz_setOptionDuration(
        uint48 timeUntilEligible_,
        uint48 eligibleDuration_
    ) public {
        vm.assume(timeUntilEligible_ <= uint48(365 days) && eligibleDuration_ <= uint48(365 days));
        _manualStrikeOLM();
        if (
            eligibleDuration_ < uint48(1 days) ||
            molm.epochDuration() > timeUntilEligible_ + eligibleDuration_ - uint48(1 days)
        ) {
            // Except revert since param is invalid
            bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
            vm.expectRevert(err);
            vm.prank(alice);
            molm.setOptionDuration(timeUntilEligible_, eligibleDuration_);
        } else {
            // Confirm that option duration was updated
            vm.prank(alice);
            molm.setOptionDuration(timeUntilEligible_, eligibleDuration_);
            assertEq(molm.eligibleDuration(), eligibleDuration_);
            assertEq(molm.timeUntilEligible(), timeUntilEligible_);
        }
    }

    /* ========== setQuoteToken ========== */

    function testRevert_setQuoteToken_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Try to set quote token as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setQuoteToken(jkl);

        // Confirm that quote token was not updated
        assertEq(address(molm.quoteToken()), address(ghi));

        // Try to set quote token as owner, expect success
        vm.prank(alice);
        molm.setQuoteToken(jkl);

        // Confirm that quote token was updated
        assertEq(address(molm.quoteToken()), address(jkl));
    }

    function testRevert_setQuoteToken_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set quote token as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setQuoteToken(jkl);

        // Confirm that receiver has not been set since the contract isn't initialized
        assertEq(address(olm_.quoteToken()), address(0));
    }

    function testRevert_setQuoteToken_invalidToken() public {
        _manualStrikeOLM();
        // Try to set quote token as owner to zero address, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setQuoteToken(ERC20(address(0)));

        // Try to set quote token as owner to an address that isn't a contract, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setQuoteToken(ERC20(bob));
    }

    function test_setQuoteToken() public {
        _manualStrikeOLM();
        // Confirm that the quote token is set to ghi
        assertEq(address(molm.quoteToken()), address(ghi));

        // Try to set quote token as owner, expect success
        vm.prank(alice);
        molm.setQuoteToken(jkl);

        // Confirm that quote token was updated
        assertEq(address(molm.quoteToken()), address(jkl));
    }

    /* ========== setStrikePrice ========== */

    function testRevert_setStrikePrice_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial strike price
        uint256 startStrikePrice = molm.strikePrice();
        assertEq(startStrikePrice, 5e18);

        // Try to set epoch duration as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setStrikePrice(1e18);

        // Confirm that strike price was not updated
        assertEq(molm.strikePrice(), startStrikePrice);

        // Try to set strike price as owner, expect success
        vm.prank(alice);
        molm.setStrikePrice(10e18);

        // Confirm that reward rate was updated
        assertEq(molm.strikePrice(), 10e18);
    }

    function testRevert_setStrikePrice_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set strike price as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setStrikePrice(10e18);

        // Confirm that reward rate has not been set since the contract isn't initialized
        assertEq(olm_.strikePrice(), 0);
    }

    function test_setStrikePrice() public {
        _manualStrikeOLM();

        // Confirm that strike price is initialized to 5e18
        assertEq(molm.strikePrice(), 5e18);

        // Try to set strike price to zero as owner, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setStrikePrice(0);

        // Confirm that strike price was not updated
        assertEq(molm.strikePrice(), 5e18);

        // Set strike price as owner
        vm.prank(alice);
        molm.setStrikePrice(10e18);

        // Confirm that strike price was updated
        assertEq(molm.strikePrice(), 10e18);
    }

    /* ========== setAllowlist ========== */

    function testRevert_setAllowlist_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _manualStrikeOLM();

        // Cache initial allowlist status
        IAllowlist startAllowlist = molm.allowlist();

        // Try to set allowlist as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        molm.setAllowlist(allowlist, abi.encode(ve, 100e18));

        // Confirm that allowlist was not updated
        assertEq(address(molm.allowlist()), address(startAllowlist));

        // Try to set allowlist as owner, expect success
        vm.prank(alice);
        molm.setAllowlist(allowlist, abi.encode(ve, 100e18));

        // Confirm that allowlist was updated
        assertEq(address(molm.allowlist()), address(allowlist));
    }

    function testRevert_setAllowlist_notInitialized() public {
        // Deploy a new molm that isn't initialized with a different address
        vm.prank(carol);
        ManualStrikeOLM olm_ = molmFactory.deploy(abc, def);

        // Confirm that the molm is not initialized
        assertFalse(olm_.initialized());

        // Try to set allowlist as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setAllowlist(allowlist, abi.encode(ve, 100e18));

        // Confirm that allowlist has not been set since the contract isn't initialized
        assertEq(address(olm_.allowlist()), address(0));
    }

    function testRevert_setAllowlist_invalidParams() public {
        _manualStrikeOLM();

        // Case 1: Allowlist is non-zero address that is not a contract
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setAllowlist(IAllowlist(bob), ZERO_BYTES);

        // Case 2: Allowlist is a contract, but does not implement the IAllowlist interface
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setAllowlist(IAllowlist(address(molmFactory)), ZERO_BYTES);

        // Case 3: Allowlist is a conforming contract, but registration fails (invalid params)
        vm.expectRevert(err);
        vm.prank(alice);
        molm.setAllowlist(allowlist, ZERO_BYTES);
    }

    function test_setAllowlist() public {
        _manualStrikeOLM();

        // Confirm that the allowlist is initialized to the zero address
        assertEq(address(molm.allowlist()), address(0));

        // Set allowlist
        vm.prank(alice);
        molm.setAllowlist(allowlist, abi.encode(ve, 100e18));

        // Confirm that allowlist was updated
        assertEq(address(molm.allowlist()), address(allowlist));

        // Confirm that allowlist registration was successful
        vm.prank(address(molm));
        bool allowed = allowlist.isAllowed(bob, ZERO_BYTES);
        assertTrue(allowed);
        vm.prank(address(molm));
        allowed = allowlist.isAllowed(carol, ZERO_BYTES);
        assertFalse(allowed);

        // Confirm bob can stake
        vm.prank(bob);
        molm.stake(100e18, ZERO_BYTES);

        // Confirm carol cannot stake
        bytes memory err = abi.encodeWithSignature("OLM_NotAllowed()");
        vm.expectRevert(err);
        vm.prank(carol);
        molm.stake(100e18, ZERO_BYTES);

        // Set the allowlist back to zero address (not used)
        vm.prank(alice);
        molm.setAllowlist(IAllowlist(address(0)), ZERO_BYTES);

        // Confirm that allowlist was updated
        assertEq(address(molm.allowlist()), address(0));

        // Confirm that bob can still stake
        vm.prank(bob);
        molm.stake(100e18, ZERO_BYTES);

        // Confirm that carol can now stake
        vm.prank(carol);
        molm.stake(100e18, ZERO_BYTES);
    }

    /* ========== currentRewardsPerToken ========== */

    function test_currentRewardsPerToken_activeBalance() public {
        _manualStrikeOLM();

        // Stake some initial tokens so rewards accrue
        vm.prank(bob);
        molm.stake(100e18, ZERO_BYTES);

        // Confirm that rewards per token is zero to start with
        assertEq(molm.currentRewardsPerToken(), 0);

        // Move forward in time 1 hour and expect rewards per token to be updated
        vm.warp(block.timestamp + 1 hours);
        assertEq(molm.currentRewardsPerToken(), (uint256(1000e18) * 1e18) / (24 * 100e18));

        // Move forward several days and expect rewards per token to be updated
        vm.warp(block.timestamp + 3 days);
        assertEq(molm.currentRewardsPerToken(), (uint256(1000e18) * 73 * 1e18) / (24 * 100e18));
    }

    function test_currentRewardsPerToken_noBalance() public {
        _manualStrikeOLM();

        // Confirm that rewards per token is zero to start with and total balance is zero
        assertEq(molm.currentRewardsPerToken(), 0);
        assertEq(molm.totalBalance(), 0);

        // Move forward in time 1 hour and expect rewards per token to still be zero
        vm.warp(block.timestamp + 1 hours);
        assertEq(molm.currentRewardsPerToken(), 0);

        // Move forward several days and expect rewards per token to be updated
        vm.warp(block.timestamp + 3 days);
        assertEq(molm.currentRewardsPerToken(), 0);
    }

    function test_currentRewardsPerToken_activeThenNoBalance() public {
        _manualStrikeOLM();

        // Stake some initial tokens so rewards accrue
        vm.prank(bob);
        molm.stake(100e18, ZERO_BYTES);

        // Confirm that rewards per token is zero to start with
        assertEq(molm.currentRewardsPerToken(), 0);

        // Move forward in time 1 hour and expect rewards per token to be updated
        vm.warp(block.timestamp + 1 hours);
        assertEq(molm.currentRewardsPerToken(), (uint256(1000e18) * 1e18) / (24 * 100e18));

        // Move forward several days and expect rewards per token to be updated
        vm.warp(block.timestamp + 3 days);
        assertEq(molm.currentRewardsPerToken(), (uint256(1000e18) * 73 * 1e18) / (24 * 100e18));

        // Withdraw all tokens (and updates rewards so current rewards are stored)
        vm.prank(bob);
        molm.unstakeAll();

        // Move forward in time another day and expect rewards per token to still be the same
        vm.warp(block.timestamp + 1 days);
        assertEq(molm.currentRewardsPerToken(), (uint256(1000e18) * 73 * 1e18) / (24 * 100e18));
    }

    /* ========== nextStrikePrice ========== */

    function test_nextStrikePrice() public {
        _manualStrikeOLM();

        // Confirm that strike price is initialized to 5e18
        assertEq(molm.strikePrice(), 5e18);

        // Expect next strike price to be same as strike price
        assertEq(molm.nextStrikePrice(), 5e18);

        // Update strike price
        vm.prank(alice);
        molm.setStrikePrice(10e18);

        // Expect next strike price to be same as strike price
        assertEq(molm.nextStrikePrice(), 10e18);
    }

    /* ========== ORACLE, FIXED STRIKE OLM TESTS ========== */
    // DONE
    // Only need to test the functions specific to the oracle implementation
    //  [X] - initialize
    //      [X] - reverts if already initialized
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if any parameters are invalid
    //          [X] - quoteToken is zero address or not a contract
    //          [X] - option eligible duration is less than minimum duration on teller
    //          [X] - option expires before the epoch duration is over
    //          [X] - receiver is zero address
    //          [X] - oracle returns zero value
    //      [X] - when initialized
    //          [X] - all data set correctly
    //          [X] - initialized is true
    //          [X] - depositEnabled is true
    //  [X] - setOracle
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if oracle is zero address or not a contract
    //      [X] - reverts if oracle returns zero value
    //      [X] - oracle is updated
    //  [X] - setOracleDiscount
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if discount is greater than or equal to 100%
    //      [X] - oracle discount is updated
    //  [X] - setMinStrikePrice
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - min strike price is updated
    //  [X] - setQuoteToken
    //      [X] - reverts if caller is not owner
    //      [X] - reverts if not initialized
    //      [X] - reverts if token is zero address or not a contract
    //      [X] - reverts if oracle returns zero value for new token pair
    //      [X] - quote token is updated
    //  [X] - nextStrikePrice
    //      [X] - updates when oracle price changes
    //      [X] - updates when oracle discount changes

    /* ========== initialize ========== */
    function testRevert_oracle_initialize_alreadyInitialized() public {
        _oracleStrikeOLM();

        // Setup initializes the contract so we shouldn't be able to initialize again
        uint8 payoutDecimals = def.decimals();
        bytes memory err = abi.encodeWithSignature("OLM_AlreadyInitialized()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 20e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );
    }

    function testRevert_oracle_initialize_notOwner(address other_) public {
        vm.assume(other_ != carol);
        _oracleStrikeOLM();

        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Try to initialize the new oolm with a different address, expect revert
        uint8 payoutDecimals = def.decimals();
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Verify that the new oolm is not initialized
        assertFalse(olm_.initialized());

        // Try to initialize the new oolm with the correct address, expect success
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Verify that the new oolm is initialized
        assertTrue(olm_.initialized());
    }

    function testRevert_oracle_initialize_invalidParameters() public {
        _oracleStrikeOLM();
        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Try to initialize the new oolm with invalid parameters, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        uint8 payoutDecimals = def.decimals();

        // Case: Quote Token is zero address
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ERC20(address(0)), // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Quote token is not a contract
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ERC20(bob), // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Eligible duration is less than the teller minimum
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(7 days), // uint48 timeUntilEligible_
            uint48(1 days) - 1, // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Option expires before epoch is over
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(5 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Receiver is zero address
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            address(0), // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Allowlist is non-zero, but doesn't conform to interface
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(bob), // IAllowlist allowlist_
            abi.encode(ve, 10e18), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Token provided to allowlist doesn't conform to ITokenBalance
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            allowlist, // IAllowlist allowlist_
            abi.encode(bob, 10e18), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Oracle address is zero
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(address(0), 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Oracle address is not a contract
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(bob, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Oracle discount is 100% or more
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 100e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Oracle price returned is less than min strike price
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 60e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Minimum strike price is zero
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 0) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Minimum strike price is too low and will result in precision loss
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e7) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Case: Oracle price is zero for quote token and payout token
        oracle.setPrice(ghi, def, 0);

        vm.expectRevert(err);
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            alice, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );
    }

    function testFuzz_oracle_initialize_durations(
        uint48 timeUntilEligible_,
        uint48 eligibleDuration_,
        uint48 epochDuration_
    ) public {
        if (
            eligibleDuration_ > uint48(365 days) ||
            timeUntilEligible_ > uint48(365 days) ||
            epochDuration_ > uint48(365 days)
        ) return;

        vm.assume(
            eligibleDuration_ >= uint48(1 days) &&
                epochDuration_ <= timeUntilEligible_ + eligibleDuration_ - uint48(1 days)
        );
        _oracleStrikeOLM();

        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Try to initialize the new oolm with fuzzed parameters, expect success
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            timeUntilEligible_, // uint48 timeUntilEligible_
            eligibleDuration_, // uint48 eligibleDuration_
            carol, // address receiver_
            epochDuration_, // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );
    }

    function test_oracle_initialize() public {
        _oracleStrikeOLM();

        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Confirm that the oolm is not initialized and deposits are not enabled
        assertFalse(olm_.initialized());
        assertFalse(olm_.depositsEnabled());

        // Initialize the new oolm
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            carol, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            IAllowlist(address(0)), // IAllowlist allowlist_
            abi.encode(0), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Verify that the oolm is initialized
        assertTrue(olm_.initialized());

        // Check that all data was set correctly
        assertEq(address(olm_.quoteToken()), address(ghi));
        assertEq(olm_.timeUntilEligible(), uint48(1 days));
        assertEq(olm_.eligibleDuration(), uint48(7 days));
        assertEq(olm_.receiver(), carol);
        assertEq(olm_.epochDuration(), uint48(7 days));
        assertEq(olm_.epochTransitionReward(), 1 * 10 ** payoutDecimals);
        assertEq(olm_.rewardRate(), 1000 * 10 ** payoutDecimals);
        assertEq(address(olm_.oracle()), address(oracle));
        assertEq(olm_.oracleDiscount(), 10e3);
        assertEq(olm_.minStrikePrice(), 5e18);
        assertEq(address(olm_.allowlist()), address(0));

        // Check that deposits are enabled and the first epoch was started
        assertTrue(olm_.depositsEnabled());
        assertEq(olm_.epoch(), uint48(1));
        assertEq(olm_.epochStart(), uint48(block.timestamp));
        assertEq(olm_.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(olm_.totalBalance(), 0);

        // Check that the option token created for the first epoch was set correctly
        FixedStrikeOptionToken optionToken = olm_.epochOptionTokens(1);
        assertEq(address(optionToken.payout()), address(def));
        assertEq(address(optionToken.quote()), address(ghi));
        assertEq(optionToken.eligible(), uint48(block.timestamp) + uint48(1 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.expiry(), uint48(block.timestamp) + uint48(8 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.receiver(), carol);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), 9 * 1e18);
    }

    function test_oracle_initialize_allowlist() public {
        _oracleStrikeOLM();

        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Confirm that the oolm is not initialized and deposits are not enabled
        assertFalse(olm_.initialized());
        assertFalse(olm_.depositsEnabled());

        // Initialize the new oolm
        uint8 payoutDecimals = def.decimals();
        vm.prank(carol);
        olm_.initialize(
            ghi, // ERC20 quoteToken_
            uint48(1 days), // uint48 timeUntilEligible_
            uint48(7 days), // uint48 eligibleDuration_
            carol, // address receiver_
            uint48(7 days), // uint48 epochDuration_
            1 * 10 ** payoutDecimals, // uint256 epochTransitionReward_
            1000 * 10 ** payoutDecimals, // uint256 rewardRate_ (per day)
            allowlist, // IAllowlist allowlist_
            abi.encode(ve, 10e18), // bytes calldata allowlistParams_
            abi.encode(oracle, 10e3, 5e18) // bytes calldata other_ (oracle, discount, min strike price in this case)
        );

        // Verify that the oolm is initialized
        assertTrue(olm_.initialized());

        // Check that all data was set correctly
        assertEq(address(olm_.quoteToken()), address(ghi));
        assertEq(olm_.timeUntilEligible(), uint48(1 days));
        assertEq(olm_.eligibleDuration(), uint48(7 days));
        assertEq(olm_.receiver(), carol);
        assertEq(olm_.epochDuration(), uint48(7 days));
        assertEq(olm_.epochTransitionReward(), 1 * 10 ** payoutDecimals);
        assertEq(olm_.rewardRate(), 1000 * 10 ** payoutDecimals);
        assertEq(address(olm_.oracle()), address(oracle));
        assertEq(olm_.oracleDiscount(), 10e3);
        assertEq(olm_.minStrikePrice(), 5e18);
        assertEq(address(olm_.allowlist()), address(allowlist));

        // Check that contract is configured correctly on the allowlist
        (ITokenBalance token, uint96 threshold) = allowlist.checks(address(olm_));
        assertEq(address(token), address(ve));
        assertEq(threshold, uint96(10e18));
        vm.prank(address(olm_));
        bool allowed = allowlist.isAllowed(bob, ZERO_BYTES);
        assertTrue(allowed);
        vm.prank(address(olm_));
        allowed = allowlist.isAllowed(carol, ZERO_BYTES);
        assertFalse(allowed);

        // Check that deposits are enabled and the first epoch was started
        assertTrue(olm_.depositsEnabled());
        assertEq(olm_.epoch(), uint48(1));
        assertEq(olm_.epochStart(), uint48(block.timestamp));
        assertEq(olm_.lastRewardUpdate(), uint48(block.timestamp));
        assertEq(olm_.totalBalance(), 0);

        // Check that the option token created for the first epoch was set correctly
        FixedStrikeOptionToken optionToken = olm_.epochOptionTokens(1);
        assertEq(address(optionToken.payout()), address(def));
        assertEq(address(optionToken.quote()), address(ghi));
        assertEq(optionToken.eligible(), uint48(block.timestamp) + uint48(1 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.expiry(), uint48(block.timestamp) + uint48(8 days)); // rounding isn't an issue here because we are at 0000 UTC
        assertEq(optionToken.receiver(), carol);
        assertEq(optionToken.call(), true);
        assertEq(optionToken.strike(), 9 * 1e18);
    }

    /* ========== setOracle ========== */
    function testRevert_setOracle_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _oracleStrikeOLM();

        // Deploy new mock oracle
        MockBondOracle oracle_ = new MockBondOracle();
        // Set quote and payout token prices on oracle so it's configured appropriately
        oracle_.setPrice(ghi, def, 2e18);
        oracle_.setDecimals(ghi, def, 18);

        // Try to set oracle as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        oolm.setOracle(oracle_);

        // Confirm that oracle was not updated
        assertEq(address(oolm.oracle()), address(oracle));

        // Try to set oracle as owner, expect success
        vm.prank(alice);
        oolm.setOracle(oracle_);

        // Confirm that quote token was updated
        assertEq(address(oolm.oracle()), address(oracle_));
    }

    function testRevert_setOracle_notInitialized() public {
        _oracleStrikeOLM();
        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Confirm that the oolm is not initialized
        assertFalse(olm_.initialized());

        // Try to set oracle as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setOracle(oracle);

        // Confirm that oracle has not been set since the contract isn't initialized
        assertEq(address(olm_.oracle()), address(0));
    }

    function testRevert_setOracle_invalidToken() public {
        _oracleStrikeOLM();
        // Try to set oracle as owner to zero address, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setOracle(MockBondOracle(address(0)));

        // Try to set oracle as owner to an address that isn't a contract, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setOracle(MockBondOracle(bob));
    }

    function testRevert_setOracle_invalidPrice() public {
        _oracleStrikeOLM();

        // Deploy new mock oracle
        MockBondOracle oracle_ = new MockBondOracle();
        // Don't set any prices so that the oracle is not configured appropriately

        // Try to set oracle as owner to a token that doesn't have a price on the oracle, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setOracle(oracle_);
    }

    function test_setOracle() public {
        _oracleStrikeOLM();

        // Deploy new mock oracle
        MockBondOracle oracle_ = new MockBondOracle();
        // Set quote and payout token prices on oracle so it's configured appropriately
        oracle_.setPrice(ghi, def, 2e18);
        oracle_.setDecimals(ghi, def, 18);

        // Confirm that the oracle is set to the base oracle
        assertEq(address(oolm.oracle()), address(oracle));

        // Try to set oracle as owner, expect success
        vm.prank(alice);
        oolm.setOracle(oracle_);

        // Confirm that oracle was updated
        assertEq(address(oolm.oracle()), address(oracle_));
    }

    /* ========== setOracleDiscount ========== */
    function testRevert_setOracleDiscount_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _oracleStrikeOLM();

        // Cache initial oracle discount
        uint48 startOracleDiscount = oolm.oracleDiscount(); // 10%

        // Try to set oracle discount as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        oolm.setOracleDiscount(50e3);

        // Confirm that oracle discount was not updated
        assertEq(oolm.oracleDiscount(), startOracleDiscount);

        // Try to set oracle discount as owner, expect success
        vm.prank(alice);
        oolm.setOracleDiscount(5e3);

        // Confirm that epoch duration was updated
        assertEq(oolm.oracleDiscount(), 5e3);
    }

    function testRevert_setOracleDiscount_notInitialized() public {
        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Confirm that the oolm is not initialized
        assertFalse(olm_.initialized());

        // Try to set oracle discount as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setOracleDiscount(5e3);

        // Confirm that oracle discount has not been set since the contract isn't initialized
        assertEq(olm_.oracleDiscount(), 0);
    }

    function testFuzz_setOracleDiscount(uint48 oracleDiscount_) public {
        _oracleStrikeOLM();
        if (oracleDiscount_ >= uint48(100e3)) {
            // Except revert since param is invalid
            bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
            vm.expectRevert(err);
            vm.prank(alice);
            oolm.setOracleDiscount(oracleDiscount_);
        } else {
            // Confirm that oracle discount was updated
            vm.prank(alice);
            oolm.setOracleDiscount(oracleDiscount_);
            assertEq(oolm.oracleDiscount(), oracleDiscount_);
        }
    }

    /* ========== setMinStrikePrice ========== */
    function testRevert_setMinStrikePrice_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _oracleStrikeOLM();

        // Cache initial min strike price
        uint256 startMinStrikePrice = oolm.minStrikePrice(); // 5e18

        // Try to set min strike price as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        oolm.setMinStrikePrice(0);

        // Confirm that oracle discount was not updated
        assertEq(oolm.minStrikePrice(), startMinStrikePrice);

        // Try to set oracle discount as owner, expect success
        vm.prank(alice);
        oolm.setMinStrikePrice(2e18);

        // Confirm that epoch duration was updated
        assertEq(oolm.minStrikePrice(), 2e18);
    }

    function testRevert_setMinStrikePrice_notInitialized() public {
        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Confirm that the oolm is not initialized
        assertFalse(olm_.initialized());

        // Try to set oracle discount as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setMinStrikePrice(1e18);

        // Confirm that oracle discount has not been set since the contract isn't initialized
        assertEq(olm_.minStrikePrice(), 0);
    }

    function testRevert_setMinStrikePrice_invalidPrice() public {
        _oracleStrikeOLM();

        // Try to set min strike price as owner to zero, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setMinStrikePrice(0);

        // Try to set min strike price as owner to a value that is too low and will result in precision loss, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setMinStrikePrice(5e7);
    }

    function test_setMinStrikePrice() public {
        _oracleStrikeOLM();

        // Confirm that min strike price is set to default
        assertEq(oolm.minStrikePrice(), 5e18);

        // Try to set min strike price as owner, expect success
        vm.prank(alice);
        oolm.setMinStrikePrice(2e18);

        // Confirm that min strike price was updated
        assertEq(oolm.minStrikePrice(), 2e18);
    }

    /* ========== setQuoteToken ========== */
    function testRevert_oracle_setQuoteToken_notOwner(address other_) public {
        vm.assume(other_ != alice);
        _oracleStrikeOLM();

        // Set price of new quote token and payout token pair on oracle
        oracle.setPrice(jkl, def, 5e18);
        oracle.setDecimals(jkl, def, 18);

        // Try to set quote token as a non-owner, expect revert
        bytes memory err = abi.encodePacked("UNAUTHORIZED");
        vm.expectRevert(err);
        vm.prank(other_);
        oolm.setQuoteToken(jkl);

        // Confirm that quote token was not updated
        assertEq(address(oolm.quoteToken()), address(ghi));

        // Try to set quote token as owner, expect success
        vm.prank(alice);
        oolm.setQuoteToken(jkl);

        // Confirm that quote token was updated
        assertEq(address(oolm.quoteToken()), address(jkl));
    }

    function testRevert_oracle_setQuoteToken_notInitialized() public {
        _oracleStrikeOLM();
        // Deploy a new oolm that isn't initialized with a different address
        vm.prank(carol);
        OracleStrikeOLM olm_ = oolmFactory.deploy(abc, def);

        // Set price of new quote token and payout token pair on oracle
        oracle.setPrice(jkl, def, 5e18);
        oracle.setDecimals(jkl, def, 18);

        // Confirm that the oolm is not initialized
        assertFalse(olm_.initialized());

        // Try to set quote token as owner, expect revert since it is not initialized
        bytes memory err = abi.encodeWithSignature("OLM_NotInitialized()");
        vm.expectRevert(err);
        vm.prank(carol);
        olm_.setQuoteToken(jkl);

        // Confirm that quote token has not been set since the contract isn't initialized
        assertEq(address(olm_.quoteToken()), address(0));
    }

    function testRevert_oracle_setQuoteToken_invalidToken() public {
        _oracleStrikeOLM();
        // Try to set quote token as owner to zero address, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setQuoteToken(ERC20(address(0)));

        // Try to set quote token as owner to an address that isn't a contract, expect revert
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setQuoteToken(ERC20(bob));
    }

    function testRevert_oracle_setQuoteToken_invalidPrice() public {
        _oracleStrikeOLM();
        // Try to set quote token as owner to a token that doesn't have a price on the oracle, expect revert
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");
        vm.expectRevert(err);
        vm.prank(alice);
        oolm.setQuoteToken(jkl);
    }

    function test_oracle_setQuoteToken() public {
        _oracleStrikeOLM();

        // Set price of new quote token and payout token pair on oracle
        oracle.setPrice(jkl, def, 5e18);
        oracle.setDecimals(jkl, def, 18);

        // Confirm that the quote token is set to ghi
        assertEq(address(oolm.quoteToken()), address(ghi));

        // Try to set quote token as owner, expect success
        vm.prank(alice);
        oolm.setQuoteToken(jkl);

        // Confirm that quote token was updated
        assertEq(address(oolm.quoteToken()), address(jkl));
    }

    /* ========== nextStrikePrice ========== */
    function test_oracle_nextStrikePrice() public {
        _oracleStrikeOLM();

        // Confirm that oracle has a starting price of 10e18 and there is a 10% discount configured
        assertEq(oracle.currentPrice(ghi, def), 10e18);
        assertEq(oolm.oracleDiscount(), 10e3);

        // Expect next strike price to be the oracle price with discount applied
        assertEq(oolm.nextStrikePrice(), 9e18);

        // Change the oracle price
        oracle.setPrice(ghi, def, 20e18);

        // Expect next strike price to be updated
        assertEq(oolm.nextStrikePrice(), 18e18);

        // Change the oracle discount
        vm.prank(alice);
        oolm.setOracleDiscount(5e3);

        // Expect next strike price to be updated
        assertEq(oolm.nextStrikePrice(), 19e18);

        // Change the oracle price to be less than the min strike price after discount
        oracle.setPrice(ghi, def, 5e18);

        // Expect next strike price to be the min strike price
        assertEq(oolm.nextStrikePrice(), 5e18);
    }

    /* ========== OLMFactory ========== */

    function testRevert_factory_deploy_invalidParams() public {
        bytes memory err = abi.encodeWithSignature("OLM_InvalidParams()");

        // Case 1: Owner is zero address
        vm.expectRevert(err);
        vm.prank(address(0));
        molmFactory.deploy(abc, def);

        // Case 2: Staked token is zero address
        vm.expectRevert(err);
        vm.prank(alice);
        molmFactory.deploy(ERC20(address(0)), def);

        // Case 3: Staked token is not a contract
        vm.expectRevert(err);
        vm.prank(alice);
        molmFactory.deploy(ERC20(bob), def);

        // Case 4: Payout token is zero address
        vm.expectRevert(err);
        vm.prank(alice);
        molmFactory.deploy(abc, ERC20(address(0)));

        // Case 5: Payout token is not a contract
        vm.expectRevert(err);
        vm.prank(alice);
        molmFactory.deploy(abc, ERC20(bob));

        // Case 6: Staked token is the same as payout token
        vm.expectRevert(err);
        vm.prank(alice);
        molmFactory.deploy(abc, abc);
    }
}
