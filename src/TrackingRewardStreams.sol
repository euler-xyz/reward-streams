// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {EVCUtil, IEVC} from "evc/utils/EVCUtil.sol";
import {Set, SetStorage} from "evc/Set.sol";
import {BaseRewardStreams} from "./BaseRewardStreams.sol";
import {ITrackingRewardStreams} from "./interfaces/IRewardStreams.sol";

/// @title TrackingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract inherits from BaseRewardStreams and implements ITrackingRewardStreams interface. It
/// allows for the rewards to be distributed to the rewarded token holders without a need to stake the shares. The
/// rewarded token contract must be compatible with the Balance Forwarder interface and the balanceTrackerHook function.
/// The balanceTrackerHook must be called with:
/// - the account's new balance when account's balance changes
/// - the current account's balance when the balance forwarding is enabled
/// - the account's balance of 0 when the balance forwarding is disabled
contract TrackingRewardStreams is BaseRewardStreams, ITrackingRewardStreams {
    using Set for SetStorage;

    /// @notice Constructor for the TrackingRewardStreams contract.
    /// @param evc The Ethereum Vault Connector contract.
    /// @param epochDuration The duration of an epoch.
    constructor(address evc, uint48 epochDuration) BaseRewardStreams(evc, epochDuration) {}

    /// @notice Executes the balance tracking hook for an account
    /// @param account The account address to execute the hook for
    /// @param newAccountBalance The new balance of the account
    /// @param forfeitRecentReward Whether to forfeit the most recent reward and not update the accumulator
    function balanceTrackerHook(
        address account,
        uint256 newAccountBalance,
        bool forfeitRecentReward
    ) external override {
        address rewarded = msg.sender;
        uint256 currentAccountBalance = accountBalances[account][rewarded];
        address[] memory rewardsArray = accountEnabledRewards[account][rewarded].get();

        for (uint256 i; i < rewardsArray.length; ++i) {
            address reward = rewardsArray[i];
            uint256 currentTotalEligible = distributionTotals[rewarded][reward].totalEligible;

            // We allocate rewards always before updating any balances
            updateRewardInternal(
                account, rewarded, reward, currentTotalEligible, currentAccountBalance, forfeitRecentReward
            );

            distributionTotals[rewarded][reward].totalEligible =
                currentTotalEligible + newAccountBalance - currentAccountBalance;
        }

        accountBalances[account][rewarded] = newAccountBalance;
    }
}
