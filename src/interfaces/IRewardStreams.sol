// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "./IBalanceTracker.sol";

interface IRewardStreams {
    function registerReward(
        address rewarded,
        address reward,
        uint40 startEpoch,
        uint128[] calldata rewardAmounts
    ) external;
    function updateReward(address rewarded, address reward, address recipient) external;
    function claimReward(address rewarded, address reward, address recipient, bool forgiveRecentReward) external;
    function enableReward(address rewarded, address reward) external;
    function disableReward(address rewarded, address reward, bool forgiveRecentReward) external;
    function earnedReward(address account, address rewarded, address reward) external view returns (uint256);
    function enabledRewards(address account, address rewarded) external view returns (address[] memory);
    function balanceOf(address account, address rewarded) external view returns (uint256);
    function totalEligible(address rewarded, address reward) external view returns (uint256);
    function rewardAmount(address rewarded, address reward) external view returns (uint256);
    function rewardAmount(address rewarded, address reward, uint40 epoch) external view returns (uint256);
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256);
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256);
    function currentEpoch() external view returns (uint40);
    function getEpoch(uint40 timestamp) external view returns (uint40);
    function getEpochStartTimestamp(uint40 epoch) external view returns (uint40);
    function getEpochEndTimestamp(uint40 epoch) external view returns (uint40);
}

interface IStakingFreeRewardStreams is IRewardStreams, IBalanceTracker {}

interface IStakingRewardStreams is IRewardStreams {
    function stake(address rewarded, uint256 amount) external;
    function unstake(address rewarded, uint256 amount, address recipient, bool forgiveRecentReward) external;
}
