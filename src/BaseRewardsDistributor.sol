// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

import "openzeppelin/utils/ReentrancyGuard.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "evc/Set.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "./interfaces/IRewardsDistributor.sol";

/// @title BaseRewardsDistributor
/// @notice This contract is a base class for rewards distributors that allow anyone to register a reward scheme for a
/// rewarded token.
abstract contract BaseRewardsDistributor is IRewardsDistributor, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    /// @notice Event emitted when a reward scheme is registered.
    event RewardRegistered(address indexed rewarded, address indexed reward, uint256 startEpoch, uint128[] amounts);

    /// @notice Event emitted when a user enables a reward token.
    event RewardEnabled(address indexed account, address indexed rewarded, address indexed reward);

    /// @notice Event emitted when a user disables a reward token.
    event RewardDisabled(address indexed account, address indexed rewarded, address indexed reward);

    /// @notice Event emitted when a reward token is claimed.
    event RewardClaimed(address indexed account, address indexed rewarded, address indexed reward, uint256 amount);

    error InvalidEpoch();
    error InvalidAmount();
    error AccumulatorOverflow();
    error TooManyRewardsEnabled();

    /// @notice Struct to store reward token amounts for even and odd epochs.
    struct BucketStorage {
        uint128 evenAmount;
        uint128 oddAmount;
    }

    /// @notice Struct to store distribution data.
    struct DistributionStorage {
        uint40 lastUpdated;
        uint160 accumulator;
        uint128 totalRegistered;
        uint128 totalClaimed;
        uint256 totalEligible;
    }

    /// @notice Struct to store earned data.
    struct EarnStorage {
        uint96 amount;
        uint160 accumulator;
    }

    IEVC public immutable EVC;
    uint40 public immutable EPOCH_DURATION;
    uint40 public constant MAX_EPOCHS_AHEAD = 5;
    uint256 public constant MAX_DISTRIBUTION_LENGTH = 25;
    uint256 public constant MAX_REWARDS_ENABLED = 5;
    uint256 internal constant SCALER = 1e18;

    mapping(address rewarded => mapping(address reward => mapping(uint256 index => BucketStorage))) internal buckets;
    mapping(address rewarded => mapping(address reward => DistributionStorage)) internal distribution;
    mapping(address account => mapping(address rewarded => SetStorage)) internal rewards;
    mapping(address account => mapping(address rewarded => uint256)) internal balances;
    mapping(address account => mapping(address rewarded => mapping(address reward => EarnStorage))) internal earned;

    /// @notice Constructor for the BaseRewardsDistributor contract.
    /// @param evc The Ethereum Vault Connector contract.
    /// @param epochDuration The duration of an epoch.
    constructor(IEVC evc, uint40 epochDuration) {
        if (epochDuration < 7 days) {
            revert InvalidEpoch();
        }

        EVC = evc;
        EPOCH_DURATION = epochDuration;
    }

    /// @notice Registers a new reward scheme.
    /// @param rewarded The rewarded token.
    /// @param reward The reward token.
    /// @param startEpoch The epoch to start the reward scheme from.
    /// @param rewardAmounts The reward token amounts for each epoch of the reward scheme.
    function registerReward(
        address rewarded,
        address reward,
        uint40 startEpoch,
        uint128[] calldata rewardAmounts
    ) public virtual override nonReentrant {
        uint40 epoch = currentEpoch();

        // if start epoch is 0, set it to the next epoch
        if (startEpoch == 0) {
            startEpoch = epoch + 1;
        }

        // start should be at most MAX_EPOCHS_AHEAD epochs in the future
        if (!(startEpoch > epoch && startEpoch <= epoch + MAX_EPOCHS_AHEAD)) {
            revert InvalidEpoch();
        }

        // distribution scheme should be at least 1 and at most MAX_DISTRIBUTION_LENGTH epochs long
        if (!(rewardAmounts.length > 0 && rewardAmounts.length <= MAX_DISTRIBUTION_LENGTH)) {
            revert InvalidAmount();
        }

        // calculate the total amount to be distributed in this distribution scheme
        uint128 totalAmount = sum(rewardAmounts);

        // initialize or update the data
        if (distribution[rewarded][reward].lastUpdated == 0) {
            distribution[rewarded][reward] = DistributionStorage({
                lastUpdated: uint40(block.timestamp),
                accumulator: 0,
                totalRegistered: totalAmount,
                totalClaimed: 0,
                totalEligible: 0
            });
        } else {
            updateReward(rewarded, reward, address(0));
            distribution[rewarded][reward].totalRegistered += totalAmount;
        }

        // sanity check for overflow (assumes supply of 1 which is the worst case scenario)
        if (SCALER * distribution[rewarded][reward].totalRegistered > type(uint160).max) {
            revert AccumulatorOverflow();
        }

        // transfer the total amount to be distributed to the contract
        uint256 oldBalance = IERC20(reward).balanceOf(address(this));
        IERC20(reward).safeTransferFrom(_msgSender(), address(this), totalAmount);

        if (IERC20(reward).balanceOf(address(this)) - oldBalance != totalAmount) {
            revert InvalidAmount();
        }

        // store the amounts to be distributed
        storeAmountsIntoBuckets(rewarded, reward, startEpoch, rewardAmounts);
    }

    /// @notice Updates the reward token data.
    /// @dev If the recipient is non-zero, the rewards earned by address(0) are transferred to the recipient.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the address(0) earned rewards.
    function updateReward(address rewarded, address reward, address recipient) public virtual override {
        address msgSender = _msgSender();

        updateRewardTokenData(
            msgSender,
            rewarded,
            reward,
            distribution[rewarded][reward].totalEligible,
            balances[msgSender][rewarded],
            false
        );

        claim(address(0), rewarded, reward, recipient);
    }

    /// @notice Claims earned reward.
    /// @dev Rewards are only transferred to the recipient if the recipient is non-zero.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the claimed reward tokens.
    /// @param forgiveRecentReward Whether to forgive the recent reward and not update the accumulator.
    function claimReward(
        address rewarded,
        address reward,
        address recipient,
        bool forgiveRecentReward
    ) public virtual override nonReentrant {
        address msgSender = _msgSender();

        updateRewardTokenData(
            msgSender,
            rewarded,
            reward,
            distribution[rewarded][reward].totalEligible,
            balances[msgSender][rewarded],
            forgiveRecentReward
        );

        claim(msgSender, rewarded, reward, recipient);
    }

    /// @notice Enable reward token.
    /// @dev There can be at most MAX_REWARDS_ENABLED rewards enabled for the reward token and the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    function enableReward(address rewarded, address reward) external virtual override {
        address msgSender = _msgSender();

        if (rewards[msgSender][rewarded].insert(reward)) {
            if (rewards[msgSender][rewarded].numElements > MAX_REWARDS_ENABLED) {
                revert TooManyRewardsEnabled();
            }

            uint256 currentBalance = balances[msgSender][rewarded];
            uint256 currentTotal = distribution[rewarded][reward].totalEligible;

            updateRewardTokenData(msgSender, rewarded, reward, currentTotal, 0, false);

            distribution[rewarded][reward].totalEligible = currentTotal + currentBalance;

            emit RewardEnabled(msgSender, rewarded, reward);
        }
    }

    /// @notice Disable reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forgiveRecentReward Whether to forgive the recent reward and not update the accumulator.
    function disableReward(address rewarded, address reward, bool forgiveRecentReward) external virtual override {
        address msgSender = _msgSender();

        if (rewards[msgSender][rewarded].remove(reward)) {
            uint256 currentBalance = balances[msgSender][rewarded];
            uint256 currentTotal = distribution[rewarded][reward].totalEligible;

            updateRewardTokenData(msgSender, rewarded, reward, currentTotal, currentBalance, forgiveRecentReward);

            distribution[rewarded][reward].totalEligible = currentTotal - currentBalance;

            emit RewardDisabled(msgSender, rewarded, reward);
        }
    }

    /// @notice Returns the earned reward token amount for a specific account and rewarded token.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The earned reward token amount for the account and rewarded token.
    function earnedReward(
        address account,
        address rewarded,
        address reward
    ) external view virtual override returns (uint256) {
        (, EarnStorage memory earnedCache, uint256 deltaZeroEarnedAmount) = getUpdateRewardTokenData(
            account, rewarded, reward, distribution[rewarded][reward].totalEligible, balances[account][rewarded], false
        );

        if (account == address(0)) {
            earnedCache.amount = addEarnedAmount(earnedCache.amount, deltaZeroEarnedAmount);
        }

        return earnedCache.amount;
    }

    /// @notice Returns enabled reward tokens for a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return An array of addresses representing the enabled reward tokens.
    function enabledRewards(
        address account,
        address rewarded
    ) external view virtual override returns (address[] memory) {
        return rewards[account][rewarded].get();
    }

    /// @notice Returns the rewarded token balance of a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return The rewarded token balance of the account.
    function balanceOf(address account, address rewarded) external view virtual override returns (uint256) {
        return balances[account][rewarded];
    }

    /// @notice Returns the total supply of the rewarded token enabled and eligible to receive the reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total supply of the rewarded token enabled and eligible to receive the reward token.
    function totalEligible(address rewarded, address reward) external view virtual override returns (uint256) {
        return distribution[rewarded][reward].totalEligible;
    }

    /// @notice Returns the reward token amount for a specific rewarded token and current epoch.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The reward token amount for the rewarded token and current epoch.
    function rewardAmount(address rewarded, address reward) public view virtual override returns (uint256) {
        return rewardAmount(rewarded, reward, currentEpoch());
    }

    /// @notice Returns the reward token amount for a specific rewarded token and epoch.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param epoch The epoch to get the reward token amount for.
    /// @return The reward token amount for the rewarded token and epoch.
    function rewardAmount(
        address rewarded,
        address reward,
        uint40 epoch
    ) public view virtual override returns (uint256) {
        BucketStorage memory bucket = buckets[rewarded][reward][bucketStorageIndex(epoch)];

        return epoch % 2 == 0 ? bucket.evenAmount : bucket.oddAmount;
    }

    /// @notice Returns the total reward token amount registered to be distributed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount distributed for the rewarded token.
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256) {
        return distribution[rewarded][reward].totalRegistered;
    }

    /// @notice Returns the total reward token amount claimed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount claimed for the rewarded token.
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256) {
        return distribution[rewarded][reward].totalClaimed;
    }

    /// @notice Returns the current epoch based on the block timestamp.
    /// @return The current epoch.
    function currentEpoch() public view override returns (uint40) {
        return getEpoch(uint40(block.timestamp));
    }

    /// @notice Returns the epoch for a given timestamp.
    /// @param timestamp The timestamp to get the epoch for.
    /// @return The epoch for the given timestamp.
    function getEpoch(uint40 timestamp) public view override returns (uint40) {
        return timestamp / EPOCH_DURATION;
    }

    /// @notice Returns the start timestamp for a given epoch.
    /// @param epoch The epoch to get the start timestamp for.
    /// @return The start timestamp for the given epoch.
    function getEpochStartTimestamp(uint40 epoch) public view override returns (uint40) {
        return epoch * EPOCH_DURATION;
    }

    /// @notice Returns the end timestamp for a given epoch.
    /// @param epoch The epoch to get the end timestamp for.
    /// @return The end timestamp for the given epoch.
    function getEpochEndTimestamp(uint40 epoch) public view override returns (uint40) {
        return getEpochStartTimestamp(epoch) + EPOCH_DURATION;
    }

    /// @notice Stores the reward token distribution amounts for a given rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param startEpoch The starting epoch for the distribution.
    /// @param amountsToBeStored The reward token amounts to be stored for each epoch.
    function storeAmountsIntoBuckets(
        address rewarded,
        address reward,
        uint40 startEpoch,
        uint128[] memory amountsToBeStored
    ) internal virtual {
        uint256 length = amountsToBeStored.length;
        uint256 endEpoch = startEpoch + length - 1;
        uint256 endIndex = bucketStorageIndex(uint40(endEpoch));

        uint256 amountsIndex = 0;
        for (uint40 i = bucketStorageIndex(startEpoch); i <= endIndex; ++i) {
            BucketStorage memory bucket = buckets[rewarded][reward][i];

            // assign amounts to the appropriate fields based on the epoch
            if (2 * i == startEpoch + amountsIndex && amountsIndex < length) {
                bucket.evenAmount += amountsToBeStored[amountsIndex++];
            }

            if (2 * i + 1 == startEpoch + amountsIndex && amountsIndex < length) {
                bucket.oddAmount += amountsToBeStored[amountsIndex++];
            }

            buckets[rewarded][reward][i] = bucket;
        }

        emit RewardRegistered(rewarded, reward, startEpoch, amountsToBeStored);
    }

    /// @notice Claims the earned reward for a specific account, rewarded token, and reward token, and transfers it to
    /// the recipient.
    /// @dev If recipient is address(0) or there is no reward to claim, this function does nothing.
    /// @param msgSender The address of the account claiming the reward.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to which the claimed reward will be transferred.
    function claim(address msgSender, address rewarded, address reward, address recipient) internal virtual {
        if (recipient == address(0)) {
            return;
        }

        uint128 amount = earned[msgSender][rewarded][reward].amount;

        // If there is a reward token to claim, transfer it to the recipient and emit an event.
        if (amount > 0) {
            uint128 totalRegistered = distribution[rewarded][reward].totalRegistered;
            uint128 totalClaimed = distribution[rewarded][reward].totalClaimed;

            assert(totalRegistered >= totalClaimed + amount);

            distribution[rewarded][reward].totalClaimed = totalClaimed + amount;
            earned[msgSender][rewarded][reward].amount = 0;

            IERC20(reward).safeTransfer(recipient, amount);
            emit RewardClaimed(msgSender, rewarded, reward, amount);
        }
    }

    /// @notice Updates the data for a specific account, rewarded token and reward token.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param currentTotal The current total amount of rewarded token enabled to get the reward token.
    /// @param currentUserBalance The current rewarded token balance of the account.
    /// @param forgiveRecentReward Whether to forgive the recent reward and not update the accumulator.
    function updateRewardTokenData(
        address account,
        address rewarded,
        address reward,
        uint256 currentTotal,
        uint256 currentUserBalance,
        bool forgiveRecentReward
    ) internal virtual {
        uint256 deltaZeroEarnedAmount;

        (distribution[rewarded][reward], earned[account][rewarded][reward], deltaZeroEarnedAmount) =
            getUpdateRewardTokenData(account, rewarded, reward, currentTotal, currentUserBalance, forgiveRecentReward);

        if (deltaZeroEarnedAmount > 0) {
            earned[address(0)][rewarded][reward].amount =
                addEarnedAmount(earned[address(0)][rewarded][reward].amount, deltaZeroEarnedAmount);
        }
    }

    /// @notice Calculates updated data for a specific account, rewarded token and reward token.
    /// @dev If necessary, this function artificially earns rewards for the address(0). It is done in order for the
    /// rewards not to get lost in case nobody else earns them.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param currentTotal The current total amount of rewarded token enabled to get the reward token.
    /// @param currentUserBalance The current rewarded token balance of the account.
    /// @param forgiveRecentReward Whether to forgive the recent reward and not update the accumulator.
    /// @return newDistribution The updated distribution storage for the rewarded token and reward token.
    /// @return newEarned The updated earned storage for the account, rewarded token, and reward token.
    /// @return deltaZeroEarnedAmount The amount of rewards earned by address(0) since the last update.
    function getUpdateRewardTokenData(
        address account,
        address rewarded,
        address reward,
        uint256 currentTotal,
        uint256 currentUserBalance,
        bool forgiveRecentReward
    )
        internal
        view
        virtual
        returns (
            DistributionStorage memory newDistribution,
            EarnStorage memory newEarned,
            uint256 deltaZeroEarnedAmount
        )
    {
        newDistribution = distribution[rewarded][reward];
        newEarned = earned[account][rewarded][reward];

        // If the distribution is not initialized, return.
        if (newDistribution.lastUpdated == 0) {
            return (newDistribution, newEarned, deltaZeroEarnedAmount);
        }

        if (!forgiveRecentReward) {
            // Get the start and end epochs based on the last updated timestamp of the distribution.
            uint40 epochStart = getEpoch(newDistribution.lastUpdated);
            uint40 epochEnd = currentEpoch();
            uint256 accumulatorDelta;
            BucketStorage memory bucket;

            for (uint40 i = epochStart; i <= epochEnd; ++i) {
                // Read the bucket storage slot only every other epoch or if it's the start epoch.
                if (i % 2 == 0 || i == epochStart) {
                    bucket = buckets[rewarded][reward][bucketStorageIndex(i)];
                }

                // Get the start and end timestamps for the given epoch.
                uint256 startTimestamp = getEpochStartTimestamp(i);
                uint256 endTimestamp = getEpochEndTimestamp(i);

                // Calculate the time elapsed in the given epoch.
                uint256 timeElapsed;
                if (block.timestamp >= startTimestamp && block.timestamp < endTimestamp) {
                    // If the epoch is still ongoing, calculate the time elapsed since the last update or the start
                    // of the epoch.
                    timeElapsed = newDistribution.lastUpdated > startTimestamp
                        ? block.timestamp - newDistribution.lastUpdated
                        : block.timestamp - startTimestamp;
                } else {
                    // If the epoch has ended, calculate the time elapsed since the last update or the entire
                    // duration of the epoch.
                    timeElapsed = newDistribution.lastUpdated > startTimestamp
                        ? endTimestamp - newDistribution.lastUpdated
                        : EPOCH_DURATION;
                }

                // Retrieve the amount of rewards for the given epoch.
                uint256 bucketAmount = i % 2 == 0 ? bucket.evenAmount : bucket.oddAmount;

                // Calculate the delta of the accumulator. In case nobody earns rewards, the total is set to 1 to allow
                // address(0) to arficially earn them. Otherwise, some portion of the rewards might get lost.
                accumulatorDelta +=
                    (SCALER * timeElapsed * bucketAmount) / EPOCH_DURATION / (currentTotal == 0 ? 1 : currentTotal);
            }

            // In case nobody earns rewards, accrue them to address(0). Otherwise, some portion of the rewards might get
            // lost.
            if (currentTotal == 0 && accumulatorDelta > 0) {
                deltaZeroEarnedAmount += accumulatorDelta / SCALER;
            }

            newDistribution.accumulator += uint160(accumulatorDelta);
            newDistribution.lastUpdated = uint40(block.timestamp);
        }

        uint256 amount = uint256(newEarned.amount)
            + (currentUserBalance * uint256(newDistribution.accumulator - newEarned.accumulator)) / SCALER;

        // give the rest of earned rewards to address(0)
        if (amount > type(uint96).max) {
            deltaZeroEarnedAmount += amount - type(uint96).max;
        }

        newEarned.amount = addEarnedAmount(newEarned.amount, amount);
        newEarned.accumulator = newDistribution.accumulator;
    }

    /// @notice Returns the bucket storage index for a given epoch.
    /// @param epoch The epoch to get the bucket storage index for.
    /// @return The bucket storage index for the given epoch.
    function bucketStorageIndex(uint40 epoch) internal pure returns (uint40) {
        return epoch / 2;
    }

    /// @notice Calculates the sum of all elements in the provided array.
    /// @dev This function will revert with InvalidAmount() if the total sum is 0 or exceeds the maximum value for
    /// uint128.
    /// @param amounts An array of uint128 values to be summed.
    /// @return The sum of all elements in the provided array.
    function sum(uint128[] calldata amounts) internal pure returns (uint128) {
        uint256 total;
        for (uint256 i; i < amounts.length; ++i) {
            total += amounts[i];
        }

        if (total == 0 || total > type(uint128).max) {
            revert InvalidAmount();
        }

        return uint128(total);
    }

    /// @notice Adds the given delta to the current earned amount.
    /// @dev This function adds the given delta to the current earned amount and caps the result at the maximum value
    /// for uint96.
    /// @param current The current earned amount.
    /// @param delta The amount to add to the current earned amount.
    /// @return The updated earned amount.
    function addEarnedAmount(uint256 current, uint256 delta) internal pure returns (uint96) {
        current += delta;

        if (current > type(uint96).max) {
            current = type(uint96).max;
        }

        return uint96(current);
    }

    /// @notice Retrieves the message sender in the context of the EVC.
    /// @dev This function returns the account on behalf of which the current operation is being performed, which is
    /// either msg.sender or the account authenticated by the EVC.
    /// @return The address of the message sender.
    function _msgSender() internal view virtual returns (address) {
        address sender = msg.sender;

        if (sender == address(EVC)) {
            (sender,) = EVC.getCurrentOnBehalfOfAccount(address(0));
        }

        return sender;
    }
}
