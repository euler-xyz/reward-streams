// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.24;

import "../../src/BaseRewardStreams.sol";

contract BaseRewardStreamsHarness is BaseRewardStreams {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    constructor(address evc, uint48 epochDuration) BaseRewardStreams(evc, epochDuration) {}

    function setDistributionAmount(address rewarded, address reward, uint48 epoch, uint128 amount) external {
        distributions[rewarded][reward].amounts[epoch / EPOCHS_PER_SLOT][epoch % EPOCHS_PER_SLOT] = amount;
    }

    function getDistributionData(
        address rewarded,
        address reward
    )
        external
        view
        returns (
            uint48, /* lastUpdated */
            uint208, /* accumulator */
            uint256, /* totalEligible */
            uint128, /* totalRegistered */
            uint128 /* totalClaimed */
        )
    {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        return (
            distributionStorage.lastUpdated,
            distributionStorage.accumulator,
            distributionStorage.totalEligible,
            distributionStorage.totalRegistered,
            distributionStorage.totalClaimed
        );
    }

    function setDistributionData(
        address rewarded,
        address reward,
        uint48 lastUpdated,
        uint160 accumulator,
        uint256 totalEligible,
        uint128 totalRegistered,
        uint128 totalClaimed
    ) external {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        distributionStorage.lastUpdated = lastUpdated;
        distributionStorage.accumulator = accumulator;
        distributionStorage.totalEligible = totalEligible;
        distributionStorage.totalRegistered = totalRegistered;
        distributionStorage.totalClaimed = totalClaimed;
    }

    function getDistributionTotals(
        address rewarded,
        address reward
    ) external view returns (uint256, uint128, uint128) {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        return
            (distributionStorage.totalEligible, distributionStorage.totalRegistered, distributionStorage.totalClaimed);
    }

    function getEpochData(address rewarded, address reward, uint48 epoch) external view returns (uint256) {
        mapping(uint256 => uint128[EPOCHS_PER_SLOT]) storage storageAmounts = distributions[rewarded][reward].amounts;
        return storageAmounts[epoch / EPOCHS_PER_SLOT][epoch % EPOCHS_PER_SLOT];
    }

    function setDistributionTotals(
        address rewarded,
        address reward,
        uint256 totalEligible,
        uint128 totalRegistered,
        uint128 totalClaimed
    ) external {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        distributionStorage.totalEligible = totalEligible;
        distributionStorage.totalRegistered = totalRegistered;
        distributionStorage.totalClaimed = totalClaimed;
    }

    function getAccountBalance(address account, address rewarded) external view returns (uint256) {
        return accounts[account][rewarded].balance;
    }

    function setAccountBalance(address account, address rewarded, uint256 balance) external {
        accounts[account][rewarded].balance = balance;
    }

    function insertReward(address account, address rewarded, address reward) external {
        accounts[account][rewarded].enabledRewards.insert(reward);
    }

    function isRewardEnabled(address account, address rewarded, address reward) external view returns (bool) {
        return accounts[account][rewarded].enabledRewards.contains(reward);
    }

    function getAccountEarnedData(
        address account,
        address rewarded,
        address reward
    ) external view returns (EarnStorage memory) {
        return accounts[account][rewarded].earned[reward];
    }

    function setAccountEarnedData(
        address account,
        address rewarded,
        address reward,
        EarnStorage memory earnStorage
    ) external {
        accounts[account][rewarded].earned[reward] = earnStorage;
    }

    function getTimeElapsedInEpoch(uint48 epoch, uint48 lastUpdated) external view returns (uint256) {
        return timeElapsedInEpoch(epoch, lastUpdated);
    }

    function getUpdatedAccumulator(address rewarded, address reward) external view returns (uint160) {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        EarnStorage storage earnStorage = accounts[msg.sender][rewarded].earned[reward];
        (, uint160 accumulator,,) = calculateRewards(distributionStorage, earnStorage, 0, false);
        return accumulator;
    }

    function timeElapsedInEpochPublic(uint48 epoch, uint48 lastUpdated) external view returns (uint256) {
        return timeElapsedInEpoch(epoch, lastUpdated);
    }

    function msgSender() external view returns (address) {
        return _msgSender();
    }
}
