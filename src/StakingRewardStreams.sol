// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Set, SetStorage} from "evc/Set.sol";
import {BaseRewardStreams} from "./BaseRewardStreams.sol";
import {IStakingRewardStreams} from "./interfaces/IRewardStreams.sol";

/// @title StakingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract inherits from BaseRewardStreams and implements IStakingRewardStreams interface.
/// It allows for the rewards to be distributed to the rewarded token holders who have staked it.
contract StakingRewardStreams is BaseRewardStreams, IStakingRewardStreams {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    /// @notice Event emitted when a user stakes tokens.
    event Staked(address indexed account, address indexed rewarded, uint256 amount);

    /// @notice Event emitted when a user unstakes tokens.
    event Unstaked(address indexed account, address indexed rewarded, uint256 amount);

    /// @notice Constructor for the StakingRewardStreams contract.
    /// @param evc The Ethereum Vault Connector contract.
    /// @param periodDuration The duration of a period.
    constructor(address evc, uint48 periodDuration) BaseRewardStreams(evc, periodDuration) {}

    /// @notice Allows a user to stake rewarded tokens.
    /// @dev If the amount is max, the entire balance of the user is staked.
    /// @param rewarded The address of the rewarded token.
    /// @param amount The amount of tokens to stake.
    function stake(address rewarded, uint256 amount) external virtual override nonReentrant {
        address msgSender = _msgSender();

        if (amount == type(uint256).max) {
            amount = IERC20(rewarded).balanceOf(msgSender);
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        AccountStorage storage account = accountStorage[msgSender][rewarded];
        uint256 currentAccountBalance = account.balance;
        address[] memory rewards = account.enabledRewards.get();

        for (uint256 i = 0; i < rewards.length; ++i) {
            address reward = rewards[i];
            Distribution storage distribution = distributions[rewarded][reward];
            uint256 currentTotalEligible = distribution.totalEligible;

            // We allocate rewards always before updating any balances
            updateRewardInternal(account, rewarded, reward, currentAccountBalance, false);

            distribution.totalEligible = currentTotalEligible + amount;
        }

        account.balance = currentAccountBalance + amount;

        pullToken(IERC20(rewarded), msgSender, amount);

        emit Staked(msgSender, rewarded, amount);
    }

    /// @notice Allows a user to unstake rewarded tokens.
    /// @dev If the amount is max, the entire balance of the user is unstaked.
    /// @param rewarded The address of the rewarded token.
    /// @param recipient The address to receive the unstaked tokens.
    /// @param amount The amount of tokens to unstake.
    /// @param forfeitRecentReward Whether to forfeit the recent reward and not update the accumulator.
    function unstake(
        address rewarded,
        uint256 amount,
        address recipient,
        bool forfeitRecentReward
    ) external virtual override nonReentrant {
        address msgSender = _msgSender();
        AccountStorage storage account = accountStorage[msgSender][rewarded];
        uint256 currentAccountBalance = account.balance;

        if (amount == type(uint256).max) {
            amount = currentAccountBalance;
        }

        if (amount == 0 || amount > currentAccountBalance) {
            revert InvalidAmount();
        }

        address[] memory rewards = account.enabledRewards.get();

        for (uint256 i = 0; i < rewards.length; ++i) {
            address reward = rewards[i];
            Distribution storage distribution = distributions[rewarded][reward];
            uint256 currentTotalEligible = distribution.totalEligible;

            // We allocate rewards always before updating any balances
            updateRewardInternal(account, rewarded, reward, currentAccountBalance, forfeitRecentReward);

            distribution.totalEligible = currentTotalEligible - amount;
        }

        account.balance = currentAccountBalance - amount;

        IERC20(rewarded).safeTransfer(recipient, amount);

        emit Unstaked(msgSender, rewarded, amount);
    }
}
