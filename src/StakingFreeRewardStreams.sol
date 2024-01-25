// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

import "./BaseRewardStreams.sol";
import "./interfaces/IBalanceForwarder.sol";

/// @title StakingFreeRewardStreams
/// @notice This contract inherits from BaseRewardStreams and implements IStakingFreeRewardStreams interface. It
/// allows for the rewards to be distributed to the rewarded token holders without a need to stake the shares. The
/// rewarded token contract must be compatible with the Balance Forwarder interface and the balanceTrackerHook function.
/// The balanceTrackerHook must be called with:
/// - the account's new balance when account's balance changes
/// - the current account's balance when the balance forwarding is enabled
/// - the account's balance of 0 when the balance forwarding is disabled
contract StakingFreeRewardStreams is BaseRewardStreams, IStakingFreeRewardStreams {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    /// @notice Constructor for the StakingFreeRewardStreams contract.
    /// @param evc The Ethereum Vault Connector contract.
    /// @param epochDuration The duration of an epoch.
    constructor(IEVC evc, uint40 epochDuration) BaseRewardStreams(evc, epochDuration) {}

    /// @notice Executes the balance tracking hook for an account
    /// @param account The account address to execute the hook for
    /// @param newBalance The new balance of the account
    /// @param forgiveRecentReward Whether to forgive the most recent reward and not update the accumulator
    function balanceTrackerHook(address account, uint256 newBalance, bool forgiveRecentReward) external override {
        address rewarded = msg.sender;
        uint256 currentBalance = balances[account][rewarded];
        address[] memory rewardsArray = rewards[account][rewarded].get();

        for (uint256 i; i < rewardsArray.length; ++i) {
            address reward = rewardsArray[i];
            uint256 currentTotal = totals[rewarded][reward].totalEligible;

            updateRewardTokenData(account, rewarded, reward, currentTotal, currentBalance, forgiveRecentReward);

            totals[rewarded][reward].totalEligible = currentTotal + newBalance - currentBalance;
        }

        balances[account][rewarded] = newBalance;
    }
}
