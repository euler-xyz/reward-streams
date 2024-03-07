// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

import "openzeppelin/utils/ReentrancyGuard.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "evc/utils/EVCUtil.sol";
import "evc/Set.sol";
import "./interfaces/IRewardStreams.sol";

/// @title BaseRewardStreams
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract is a base class for rewards distributors that allow anyone to register a reward scheme for a
/// rewarded token.
abstract contract BaseRewardStreams is IRewardStreams, EVCUtil, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Set for SetStorage;

    uint256 public immutable EPOCH_DURATION;
    uint256 public constant MAX_EPOCHS_AHEAD = 5;
    uint256 public constant MAX_DISTRIBUTION_LENGTH = 25;
    uint256 public constant MAX_REWARDS_ENABLED = 5;
    uint256 internal constant EPOCHS_PER_SLOT = 2;
    uint256 internal constant SCALER = 1e18;

    /// @notice Event emitted when a reward scheme is registered.
    event RewardRegistered(
        address indexed caller, address indexed rewarded, address indexed reward, uint256 startEpoch, uint128[] amounts
    );

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

    /// @notice Struct to store distribution data per rewarded and reward tokens.
    struct DistributionStorage {
        uint40 lastUpdated;
        uint160 accumulator;
    }

    /// @notice Struct to store totals data per rewarded and reward tokens.
    struct TotalsStorage {
        uint256 totalEligible; // Total rewarded token that are eligible for rewards
        uint128 totalRegistered; // Total reward token that have been transferred into this contract for rewards
        uint128 totalClaimed; // Total reward token that have been transferred out from this contract for rewards
    }

    /// @notice Struct to store earned data.
    struct EarnStorage {
        uint96 amount; // Claimable amount, not total earned
        uint160 accumulator;
    }

    mapping(address rewarded => mapping(address reward => mapping(uint256 storageIndex => uint128[EPOCHS_PER_SLOT])))
        internal distributionAmounts;

    mapping(address rewarded => mapping(address reward => DistributionStorage)) internal distributionData;
    mapping(address rewarded => mapping(address reward => TotalsStorage)) internal distributionTotals;

    mapping(address account => mapping(address rewarded => SetStorage)) internal accountEnabledRewards;
    mapping(address account => mapping(address rewarded => uint256)) internal accountBalances;
    mapping(address account => mapping(address rewarded => mapping(address reward => EarnStorage))) internal
        accountEarnedData;

    /// @notice Constructor for the BaseRewardStreams contract.
    /// @param _evc The Ethereum Vault Connector contract.
    /// @param _epochDuration The duration of an epoch.
    constructor(IEVC _evc, uint40 _epochDuration) EVCUtil(_evc) {
        if (_epochDuration < 7 days) {
            revert InvalidEpoch();
        }

        EPOCH_DURATION = _epochDuration;
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
    ) external virtual override nonReentrant {
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
        if (rewardAmounts.length == 0 || rewardAmounts.length > MAX_DISTRIBUTION_LENGTH) {
            revert InvalidAmount();
        }

        // calculate the total amount to be distributed in this distribution scheme
        uint256 totalAmount;
        for (uint256 i; i < rewardAmounts.length; ++i) {
            totalAmount += rewardAmounts[i];
        }

        if (totalAmount == 0) { // If we check this, shouldn't we check that there are rewards allocated for each epoch?
            revert InvalidAmount();
        }

        // initialize or update the data
        if (distributionData[rewarded][reward].lastUpdated == 0) {
            distributionData[rewarded][reward].lastUpdated = uint40(block.timestamp);
        } else {
            updateReward(rewarded, reward, address(0)); // See comment below in `updateReward`. The last parameter should be removed.
        }

        // sanity check for overflow (assumes total eligible supply of 1 which is the worst case scenario)
        uint256 totalRegistered = uint256(distributionTotals[rewarded][reward].totalRegistered) + totalAmount;

        if (SCALER * totalRegistered > type(uint160).max) {
            revert AccumulatorOverflow();
        }

        // update the total registered amount
        distributionTotals[rewarded][reward].totalRegistered = uint128(totalRegistered);

        // store the amounts to be distributed
        storeAmounts(rewarded, reward, startEpoch, rewardAmounts);

        // transfer the total amount to be distributed to the contract
        address msgSender = _msgSender();
        pullToken(IERC20(reward), msgSender, totalAmount);

        emit RewardRegistered(msgSender, rewarded, reward, startEpoch, rewardAmounts);
    }

    /// @notice Updates the reward token data.
    /// @dev If the recipient is non-zero, the rewards earned by address(0) are transferred to the recipient.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the address(0) earned rewards.
    function updateReward(address rewarded, address reward, address recipient) public virtual override {
        address msgSender = _msgSender();

        // If the account disables the rewards we pass an account balance of zero to not accrue any.
        uint256 currentAccountBalance =
            accountEnabledRewards[msgSender][rewarded].contains(reward) ? accountBalances[msgSender][rewarded] : 0;

        updateData(
            msgSender,
            rewarded,
            reward,
            distributionTotals[rewarded][reward].totalEligible,
            currentAccountBalance,
            false
        );

        claim(address(0), rewarded, reward, recipient); // It seems strange to add this call here. It would make more sense to add a completely separate function to claim spillover rewards.
    }

    /// @notice Claims earned reward.
    /// @dev Rewards are only transferred to the recipient if the recipient is non-zero.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the claimed reward tokens.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function claimReward(
        address rewarded,
        address reward,
        address recipient,
        bool forfeitRecentReward
    ) external virtual override nonReentrant {
        address msgSender = _msgSender();

        // If the account disables the rewards we pass an account balance of zero to not accrue any.
        uint256 currentAccountBalance =
            accountEnabledRewards[msgSender][rewarded].contains(reward) ? accountBalances[msgSender][rewarded] : 0;

        updateData(
            msgSender,
            rewarded,
            reward,
            distributionTotals[rewarded][reward].totalEligible,
            currentAccountBalance,
            forfeitRecentReward
        );

        claim(msgSender, rewarded, reward, recipient);
    }

    /// @notice Enable reward token.
    /// @dev There can be at most MAX_REWARDS_ENABLED rewards enabled for the reward token and the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    function enableReward(address rewarded, address reward) external virtual override {
        address msgSender = _msgSender();

        if (accountEnabledRewards[msgSender][rewarded].insert(reward)) {
            if (accountEnabledRewards[msgSender][rewarded].numElements > MAX_REWARDS_ENABLED) {
                revert TooManyRewardsEnabled();
            }

            uint256 currentAccountBalance = accountBalances[msgSender][rewarded];
            uint256 currentTotalEligible = distributionTotals[rewarded][reward].totalEligible;

            // We pass zero as `currentAccountBalance` to not distribute rewards for the period before the account enabled them
            updateData(msgSender, rewarded, reward, currentTotalEligible, 0, false);

            distributionTotals[rewarded][reward].totalEligible = currentTotalEligible + currentAccountBalance;

            emit RewardEnabled(msgSender, rewarded, reward);
        }
    }

    /// @notice Disable reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function disableReward(address rewarded, address reward, bool forfeitRecentReward) external virtual override {
        address msgSender = _msgSender();

        if (accountEnabledRewards[msgSender][rewarded].remove(reward)) {
            uint256 currentAccountBalance = accountBalances[msgSender][rewarded];
            uint256 currentTotalEligible = distributionTotals[rewarded][reward].totalEligible;

            updateData(msgSender, rewarded, reward, currentTotalEligible, currentAccountBalance, forfeitRecentReward);

            distributionTotals[rewarded][reward].totalEligible = currentTotalEligible - currentAccountBalance;

            emit RewardDisabled(msgSender, rewarded, reward);
        }
    }

    /// @notice Returns the earned reward token amount for a specific account and rewarded token.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return The earned reward token amount for the account and rewarded token.
    function earnedReward(
        address account,
        address rewarded,
        address reward,
        bool forfeitRecentReward
    ) external view virtual override returns (uint256) {
        EarnStorage memory accountEarned = accountEarnedData[account][rewarded][reward];

        // If the account disables the rewards we pass an account balance of zero to not accrue any.
        uint256 currentAccountBalance =
            accountEnabledRewards[account][rewarded].contains(reward) ? accountBalances[account][rewarded] : 0;

        uint256 deltaAccountZero = getUpdatedData(
            distributionData[rewarded][reward],
            accountEarned,
            rewarded,
            reward,
            distributionTotals[rewarded][reward].totalEligible,
            currentAccountBalance,
            forfeitRecentReward
        );

        // If we have spillover rewards, we add them to address(0), capping the address(0) rewards at MAXUINT96
        if (account == address(0) && deltaAccountZero != 0) {
            (accountEarned.amount,) = _addDeltaToCurrents(accountEarned.amount, 0, deltaAccountZero);
        }

        return accountEarned.amount;
    }

    /// @notice Returns enabled reward tokens for a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return An array of addresses representing the enabled reward tokens.
    function enabledRewards(
        address account,
        address rewarded
    ) external view virtual override returns (address[] memory) {
        return accountEnabledRewards[account][rewarded].get();
    }

    /// @notice Returns the rewarded token balance of a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return The rewarded token balance of the account.
    function balanceOf(address account, address rewarded) external view virtual override returns (uint256) {
        return accountBalances[account][rewarded];
    }

    /// @notice Returns the reward token amount for a specific rewarded token and current epoch.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The reward token amount for the rewarded token and current epoch.
    function rewardAmount(address rewarded, address reward) external view virtual override returns (uint256) {
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
        return distributionAmounts[rewarded][reward][_storageIndex(epoch)][_epochIndex(epoch)];
    }

    /// @notice Returns the total supply of the rewarded token enabled and eligible to receive the reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total supply of the rewarded token enabled and eligible to receive the reward token.
    function totalRewardedEligible(address rewarded, address reward) external view virtual override returns (uint256) {
        return distributionTotals[rewarded][reward].totalEligible;
    }

    /// @notice Returns the total reward token amount registered to be distributed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount distributed for the rewarded token.
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256) {
        return distributionTotals[rewarded][reward].totalRegistered;
    }

    /// @notice Returns the total reward token amount claimed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount claimed for the rewarded token.
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256) {
        return distributionTotals[rewarded][reward].totalClaimed;
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
        return uint40(timestamp / EPOCH_DURATION);
    }

    /// @notice Returns the start timestamp for a given epoch.
    /// @param epoch The epoch to get the start timestamp for.
    /// @return The start timestamp for the given epoch.
    function getEpochStartTimestamp(uint40 epoch) public view override returns (uint40) {
        return uint40(epoch * EPOCH_DURATION);
    }

    /// @notice Returns the end timestamp for a given epoch.
    /// @param epoch The epoch to get the end timestamp for.
    /// @return The end timestamp for the given epoch.
    function getEpochEndTimestamp(uint40 epoch) public view override returns (uint40) {
        return uint40(getEpochStartTimestamp(epoch) + EPOCH_DURATION);
    } // Is it a problem that each epochEndTimestamp overlaps the next epochStartTimestamp?

    /// @notice Stores the reward token distribution amounts for a given rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param startEpoch The starting epoch for the distribution.
    /// @param amountsToBeStored The reward token amounts to be stored for each epoch.
    function storeAmounts(
        address rewarded,
        address reward,
        uint40 startEpoch,
        uint128[] memory amountsToBeStored
    ) internal virtual {
        uint256 length = amountsToBeStored.length;
        uint256 startStorageIndex = _storageIndex(startEpoch);
        uint256 endStorageIndex = _storageIndex(startEpoch + length - 1);

        uint256 memoryIndex;
        uint128[EPOCHS_PER_SLOT] memory amounts;
        for (uint256 i = startStorageIndex; i <= endStorageIndex; ++i) {
            amounts = distributionAmounts[rewarded][reward][i];

            // assign amounts to the appropriate indices based on the epoch
            for (uint256 j = _epochIndex(startEpoch + memoryIndex); j < EPOCHS_PER_SLOT && memoryIndex < length; ++j) {
                unchecked {
                    amounts[j] += amountsToBeStored[memoryIndex++];
                }
            }

            distributionAmounts[rewarded][reward][i] = amounts;
        }
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

        uint128 amount = accountEarnedData[msgSender][rewarded][reward].amount;

        // If there is a reward token to claim, transfer it to the recipient and emit an event.
        if (amount != 0) {
            uint128 totalRegistered = distributionTotals[rewarded][reward].totalRegistered;
            uint128 totalClaimed = distributionTotals[rewarded][reward].totalClaimed;

            assert(totalRegistered >= totalClaimed + amount);

            distributionTotals[rewarded][reward].totalClaimed = totalClaimed + amount;
            accountEarnedData[msgSender][rewarded][reward].amount = 0;

            IERC20(reward).safeTransfer(recipient, amount);
            emit RewardClaimed(msgSender, rewarded, reward, amount);
        }
    }

    /// @notice Updates the data for a specific account, rewarded token and reward token.
    /// @dev If required, this function artificially accumulates rewards for the address(0) to avoid loss of rewards
    /// that wouldn't be claimable by anyone else.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param currentTotalEligible The current total amount of rewarded token eligible to get the reward token.
    /// @param currentAccountBalance The current rewarded token balance of the account.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function updateData(
        address account,
        address rewarded,
        address reward,
        uint256 currentTotalEligible,
        uint256 currentAccountBalance,
        bool forfeitRecentReward
    ) internal virtual {
        DistributionStorage memory distribution = distributionData[rewarded][reward];
        EarnStorage memory accountEarned = accountEarnedData[account][rewarded][reward];

        uint256 deltaAccountZero = getUpdatedData(
            distribution,
            accountEarned,
            rewarded,
            reward,
            currentTotalEligible,
            currentAccountBalance,
            forfeitRecentReward
        );

        distributionData[rewarded][reward] = distribution;
        accountEarnedData[account][rewarded][reward] = accountEarned;

        // If there were excess rewards, allocate them to address(0). If the rewards allocated at address(0) reach MAXUINT96, do not allocate any excess anywhere.
        if (deltaAccountZero != 0) {
            (accountEarnedData[address(0)][rewarded][reward].amount,) =
                _addDeltaToCurrents(accountEarnedData[address(0)][rewarded][reward].amount, 0, deltaAccountZero);
        }
    }

    /// @notice Computes updated data for a specific account, rewarded token, and reward token.
    /// @param distribution The distribution storage memory, which is modified by this function.
    /// @param accountEarned The account earned storage memory, which is modified by this function.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param currentTotalEligible The current total amount of rewarded token eligible to get the reward token.
    /// @param currentAccountBalance The current rewarded token balance of the account.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return deltaAccountZero Amount to be credited to address(0) in case rewards were to be lost.
    function getUpdatedData(
        DistributionStorage memory distribution,
        EarnStorage memory accountEarned,
        address rewarded,
        address reward,
        uint256 currentTotalEligible,
        uint256 currentAccountBalance,
        bool forfeitRecentReward
    ) internal view virtual returns (uint256 deltaAccountZero) {
        // If the distribution is not initialized, return.
        if (distribution.lastUpdated == 0) {
            return 0;
        }

        if (!forfeitRecentReward) {
            // Get the start and end epochs based on the last updated timestamp of the distribution.
            uint40 lastUpdated = distribution.lastUpdated;
            uint40 epochStart = getEpoch(lastUpdated);
            uint40 epochEnd = currentEpoch();
            uint128[EPOCHS_PER_SLOT] memory amounts;
            uint256 delta;

            // Calculate the amount of tokens since last update that should be distributed.
            for (uint40 i = epochStart; i <= epochEnd; ++i) {
                // Read the storage slot only every other epoch or if it's the start epoch.
                uint256 epochIndex = _epochIndex(i);
                if (epochIndex == 0 || i == epochStart) {
                    amounts = distributionAmounts[rewarded][reward][_storageIndex(i)];
                }

                delta += SCALER * _timeElapsedInEpoch(i, lastUpdated) * amounts[epochIndex] / EPOCH_DURATION;
            }

            // Increase the accumulator scaled by the total eligible amount earning reward. In case nobody earns
            // rewards, accrue them to address(0). Otherwise, some portion of the rewards might get lost.
            if (currentTotalEligible == 0) {
                deltaAccountZero += delta / SCALER;
            } else {
                distribution.accumulator += uint160(delta / currentTotalEligible);
            }

            // Snapshot the timestamp.
            distribution.lastUpdated = uint40(block.timestamp);
        }

        // Update account's earned amount. In case there's an overflow, cap the account rewards as MAXUINT96 and return the excess as `deltaAccountZero`.
        (accountEarned.amount, deltaAccountZero) = _addDeltaToCurrents(
            accountEarned.amount,
            deltaAccountZero,
            uint256(distribution.accumulator - accountEarned.accumulator) * currentAccountBalance / SCALER
        );

        // Snapshot new accumulator value.
        accountEarned.accumulator = distribution.accumulator;
    }

    /// @notice Transfers a specified amount of a token from a given address to this contract.
    /// @dev This function uses the ERC20 safeTransferFrom function to move tokens.
    /// It checks the balance before and after the transfer to ensure the correct amount has been transferred.
    /// If the transferred amount does not match the expected amount, it reverts the transaction.
    /// @param token The ERC20 token to transfer.
    /// @param from The address to transfer the tokens from.
    /// @param amount The amount of tokens to transfer.
    function pullToken(IERC20 token, address from, uint256 amount) internal {
        uint256 preBalance = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);

        if (token.balanceOf(address(this)) - preBalance != amount) {
            revert InvalidAmount();
        }
    }

    /// @notice Returns the storage index for a given epoch.
    /// @param epoch The epoch to get the storage index for.
    /// @return The storage index for the given epoch.
    function _storageIndex(uint256 epoch) internal pure returns (uint256) {
        return epoch / EPOCHS_PER_SLOT;
    }

    /// @notice Returns the epoch index for a given epoch.
    /// @param epoch The epoch to get the epoch index for.
    /// @return The epoch index for the given epoch.
    function _epochIndex(uint256 epoch) internal pure returns (uint256) {
        return epoch % EPOCHS_PER_SLOT;
    }

    /// @notice Calculates the time elapsed within a given epoch.
    /// @dev This function compares the current block timestamp with the start and end timestamps of the epoch.
    /// If the epoch is ongoing, it calculates the time elapsed since the last update or the start of the epoch, whichever is smaller.
    /// If the epoch has ended and there was an update since its start, it calculates the time elapsed since the last update to the end of the epoch.
    /// If the epoch has ended and there wasn't an update since its start, it returns the epoch duration.
    /// If the epoch hasn't started, then there can't be a later update yet, and we return the epoch duration. Maybe we should return zero.
    or the entire duration of the
    /// epoch.
    /// @param epoch The epoch for which to calculate the time elapsed.
    /// @param lastUpdated The timestamp of the last update.
    /// @return The time elapsed in the given epoch.
    function _timeElapsedInEpoch(uint40 epoch, uint40 lastUpdated) internal view returns (uint256) {
        // Get the start and end timestamps for the given epoch.
        uint256 startTimestamp = getEpochStartTimestamp(epoch);
        uint256 endTimestamp = getEpochEndTimestamp(epoch);

        // Calculate the time elapsed in the given epoch.
        if (block.timestamp >= startTimestamp && block.timestamp < endTimestamp) { // Here we act like the epochEndTimestamp doesn't belong to the epoch
            // If last update was in or after the given epoch, return the time elapsed since the last update. Otherwise return the time elapsed from the start of the given epoch.
            return lastUpdated > startTimestamp ? block.timestamp - lastUpdated : block.timestamp - startTimestamp;
        } else { // We also end here if the epoch hasn't started.
            // If last update was in or after the given epoch, return the time elapsed between the last update to the end of the given epoch. If the last update was before the start of the given epoch, return the epoch duration.
            return lastUpdated > startTimestamp ? endTimestamp - lastUpdated : EPOCH_DURATION; // I think that here we are returning one extra second if we are in the epoch
        }
    }

    /// @notice Adds the given delta to the first current amount up to uint96 max value. If it exceeds, it adds it to
    /// the second current.
    /// @param current1 The first current amount.
    /// @param current2 The second current amount.
    /// @param delta The amount to add to the current amounts.
    /// @return final1 The final amount of the first current after adding the delta.
    /// @return final2 The total of the second current amount after adding the remaining delta.
    function _addDeltaToCurrents(
        uint256 current1,
        uint256 current2,
        uint256 delta
    ) internal pure returns (uint96 final1, uint256 final2) {
        current1 += delta;

        if (current1 > type(uint96).max) {
            final1 = type(uint96).max;
            final2 = current2 + (current1 - type(uint96).max);
        } else {
            final1 = uint96(current1);
            final2 = uint96(current2);
        }
    }
}
