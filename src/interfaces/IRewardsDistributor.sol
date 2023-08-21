// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "openzeppelin/utils/structs/EnumerableSet.sol";

interface IRewardsDistributor {
    function registerReward(
        address vault,
        address reward,
        uint40 startEpoch,
        uint128[] calldata amounts
    ) external;

    function enableReward(address vault, address reward) external;

    function disableReward(address vault, address reward) external;

    function updateRewards(address account, address vault) external;

    function claimRewards(
        address vault,
        address[] calldata rewards,
        address recipient
    ) external;

    function rewardsEnabled(
        address account,
        address vault
    ) external view returns (address[] memory);

    function earned(
        address account,
        address vault
    ) external view returns (address[] memory, uint[] memory);

    function balanceOf(
        address account,
        address vault
    ) external view returns (uint);

    function totalSupply(
        address vault,
        address reward
    ) external view returns (uint);

    function rewardRate(
        address vault,
        address reward
    ) external view returns (uint);

    function rewardRate(
        address vault,
        address reward,
        uint40 epoch
    ) external view returns (uint);

    function totalSupplies(
        address vault,
        address[] memory reward
    ) external view returns (uint[] memory);

    function rewardRates(
        address vault,
        address[] memory reward
    ) external view returns (uint[] memory);

    function rewardRates(
        address vault,
        address[] memory reward,
        uint40 epoch
    ) external view returns (uint[] memory);

    function currentEpoch() external view returns (uint40);

    function getEpoch(uint40 timestamp) external view returns (uint40);

    function getEpochStartTimestamp(
        uint40 epoch
    ) external view returns (uint40);

    function getEpochEndTimestamp(uint40 epoch) external view returns (uint40);
}

interface IStakingRewardsDistributor is IRewardsDistributor {
    function stake(address vault, uint amount) external;

    function unstake(address vault, address recipient, uint amount) external;
}
