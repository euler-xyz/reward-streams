// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

import "./IBalanceTracker.sol";

/// @title IRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Reward Streams distributor contract
interface IRewardStreams {
    function registerReward(address rewarded, address reward, uint40 startEpoch, uint128[] calldata rewardAmounts) external;
    function updateReward(address rewarded, address reward, address recipient) external;
    function claimReward(address rewarded, address reward, address recipient, bool forfeitRecentReward) external;
    function enableReward(address rewarded, address reward) external;
    function disableReward(address rewarded, address reward, bool forfeitRecentReward) external;
    function earnedReward(address account, address rewarded, address reward, bool forfeitRecentReward) external view returns (uint256);
    function enabledRewards(address account, address rewarded) external view returns (address[] memory);
    function balanceOf(address account, address rewarded) external view returns (uint256);
    function rewardAmount(address rewarded, address reward) external view returns (uint256);
    function rewardAmount(address rewarded, address reward, uint40 epoch) external view returns (uint256);
    function totalRewardedEligible(address rewarded, address reward) external view returns (uint256);
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256);
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256);
    function currentEpoch() external view returns (uint40);
    function getEpoch(uint40 timestamp) external view returns (uint40);
    function getEpochStartTimestamp(uint40 epoch) external view returns (uint40);
    function getEpochEndTimestamp(uint40 epoch) external view returns (uint40);
}

/// @title IStakingFreeRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Staking Free Reward Streams, extends IRewardStreams and IBalanceTracker
interface IStakingFreeRewardStreams is IRewardStreams, IBalanceTracker {}

/// @title IStakingRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface for Staking Reward Streams, extends IRewardStreams with staking functionality
interface IStakingRewardStreams is IRewardStreams {
    function stake(address rewarded, uint256 amount) external;
    function unstake(address rewarded, uint256 amount, address recipient, bool forfeitRecentReward) external;
}
