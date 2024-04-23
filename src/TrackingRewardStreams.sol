// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

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
        AccountStorage storage accountStorage = accounts[account][rewarded];
        uint256 currentAccountBalance = accountStorage.balance;
        address[] memory rewards = accountStorage.enabledRewards.get();

        for (uint256 i = 0; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint256 currentTotalEligible = distributionTotals[rewarded][reward].totalEligible;

            // We allocate rewards always before updating any balances
            updateRewardInternal(
                account, rewarded, reward, currentTotalEligible, currentAccountBalance, forfeitRecentReward
            );

            distributionTotals[rewarded][reward].totalEligible =
                currentTotalEligible + newAccountBalance - currentAccountBalance;
        }

        accountStorage.balance = newAccountBalance;
    }
}
