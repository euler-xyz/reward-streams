// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.24;

import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {Set, SetStorage} from "evc/Set.sol";
import {IRewardStreams} from "./interfaces/IRewardStreams.sol";

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
    uint256 internal constant MIN_EPOCH_DURATION = 7 days;
    uint256 internal constant EPOCHS_PER_SLOT = 2;

    // this value is used to increase the precision of the calculations due to the fact that distributed amount of
    // rewards must be divided by the total eligible amount. 1e12 value is carefully chosen to allow big enough
    // total registered amount, per rewarded and reward token pair, while not allowing the accumulator to overflow.
    uint256 internal constant SCALER = 1e12;

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

    /// @notice Epoch-related error. Thrown when epoch duration or start epoch is invalid.
    error InvalidEpoch();

    /// @notice Amount-related error. Thrown when the reward amount is invalid or invalid amount of tokens was
    /// transferred.
    error InvalidAmount();

    /// @notice Distribution-related error. Thrown when the reward distribution length is invalid.
    error InvalidDistribution();

    /// @notice Accumulator-related error. Thrown when the registered reward amount may cause an accumulator overflow.
    error AccumulatorOverflow();

    /// @notice Rewards-related error. Thrown when user tries to enable too many rewards.
    error TooManyRewardsEnabled();

    /// @notice Recipient-related error. Throws when the recipient is invalid.
    error InvalidRecipient();

    /// @notice Struct to store distribution data per rewarded and reward tokens.
    struct DistributionStorage {
        /// @notice The last timestamp when the distribution was updated.
        uint48 lastUpdated;
        /// @notice The most recent accumulator value.
        uint208 accumulator;
        /// @notice Total rewarded token that are eligible for rewards.
        uint256 totalEligible;
        /// @notice Total reward token that have been transferred into this contract for rewards.
        uint128 totalRegistered;
        /// @notice Total reward token that have been transferred out from this contract for rewards.
        uint128 totalClaimed;
        /// @notice Distribution amounts per epoch.
        mapping(uint256 storageIndex => uint128[EPOCHS_PER_SLOT]) amounts;
    }

    /// @notice Struct to store earned data.
    struct EarnStorage {
        /// @notice Claimable amount, not total earned.
        uint112 claimable;
        /// @notice Snapshot of the accumulator at the time of the last data update.
        uint144 accumulator;
    }

    /// @notice Struct to store account data per account and rewarded token.
    struct AccountStorage {
        /// @notice The account's rewarded token balance.
        uint256 balance;
        /// @notice The account's set of enabled reward tokens.
        SetStorage enabledRewards;
        /// @notice The accont's earnins per reward token.
        mapping(address reward => EarnStorage) earned;
    }

    /// @notice Stored distribution data per rewarded token and reward token.
    mapping(address rewarded => mapping(address reward => DistributionStorage)) internal distributions;

    /// @notice Stored account data per address and rewarded token.
    mapping(address account => mapping(address rewarded => AccountStorage)) internal accounts;

    /// @notice Constructor for the BaseRewardStreams contract.
    /// @param _evc The Ethereum Vault Connector contract.
    /// @param _epochDuration The duration of an epoch.
    constructor(address _evc, uint48 _epochDuration) EVCUtil(_evc) {
        if (_epochDuration < MIN_EPOCH_DURATION) {
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
        uint48 startEpoch,
        uint128[] calldata rewardAmounts
    ) external virtual override nonReentrant {
        uint48 epoch = currentEpoch();

        // If start epoch is 0, set it to the next epoch.
        if (startEpoch == 0) {
            startEpoch = epoch + 1;
        }

        // Start should be at most MAX_EPOCHS_AHEAD epochs in the future.
        if (!(startEpoch > epoch && startEpoch <= epoch + MAX_EPOCHS_AHEAD)) {
            revert InvalidEpoch();
        }

        // Distribution scheme should be at most MAX_DISTRIBUTION_LENGTH epochs long.
        if (rewardAmounts.length > MAX_DISTRIBUTION_LENGTH) {
            revert InvalidDistribution();
        }

        // Calculate the total amount to be distributed in this distribution scheme.
        uint256 totalAmount;
        for (uint256 i = 0; i < rewardAmounts.length; ++i) {
            totalAmount += rewardAmounts[i];
        }

        if (totalAmount == 0) {
            revert InvalidAmount();
        }

        // Initialize or update the distribution and reward data.
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        if (distributionStorage.lastUpdated == 0) {
            distributionStorage.lastUpdated = uint48(block.timestamp);
        } else {
            updateReward(rewarded, reward);
        }

        // Sanity check for overflow (assumes total eligible supply of 1 which is the worst case scenario).
        uint256 totalRegistered = uint256(distributionStorage.totalRegistered) + totalAmount;

        if (SCALER * totalRegistered > type(uint144).max) {
            revert AccumulatorOverflow();
        }

        // Update the total registered amount.
        // Overflow safe because `type(uint144).max / SCALER < type(uint128).max`.
        distributionStorage.totalRegistered = uint128(totalRegistered);

        // Store the amounts to be distributed.
        increaseRewardAmounts(rewarded, reward, startEpoch, rewardAmounts);

        // Transfer the total amount to be distributed to the contract.
        address msgSender = _msgSender();
        pullToken(IERC20(reward), msgSender, totalAmount);

        emit RewardRegistered(msgSender, rewarded, reward, startEpoch, rewardAmounts);
    }

    /// @notice Updates the reward token data.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    function updateReward(address rewarded, address reward) public virtual override {
        address msgSender = _msgSender();

        // If the account disables the rewards we pass an account balance of zero to not accrue any.
        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        uint256 currentAccountBalance = accountStorage.enabledRewards.contains(reward) ? accountStorage.balance : 0;

        updateRewardInternal(
            distributions[rewarded][reward], accountStorage, rewarded, reward, currentAccountBalance, false
        );
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
        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        uint256 currentAccountBalance = accountStorage.enabledRewards.contains(reward) ? accountStorage.balance : 0;

        updateRewardInternal(
            distributions[rewarded][reward],
            accountStorage,
            rewarded,
            reward,
            currentAccountBalance,
            forfeitRecentReward
        );

        claim(msgSender, rewarded, reward, recipient);
    }

    /// @notice Claims spillover rewards.
    /// @dev Rewards are only transferred to the recipient if the recipient is non-zero.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to receive the claimed reward tokens.
    function claimSpilloverReward(
        address rewarded,
        address reward,
        address recipient
    ) external virtual override nonReentrant {
        claim(address(0), rewarded, reward, recipient);
    }

    /// @notice Enable reward token.
    /// @dev There can be at most MAX_REWARDS_ENABLED rewards enabled for the reward token and the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    function enableReward(address rewarded, address reward) external virtual override {
        address msgSender = _msgSender();
        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        SetStorage storage accountEnabledRewards = accountStorage.enabledRewards;

        if (accountEnabledRewards.insert(reward)) {
            if (accountEnabledRewards.numElements > MAX_REWARDS_ENABLED) {
                revert TooManyRewardsEnabled();
            }

            DistributionStorage storage distributionStorage = distributions[rewarded][reward];
            uint256 currentAccountBalance = accountStorage.balance;

            // We pass zero as `currentAccountBalance` to not distribute rewards for the period before the account
            // enabled them.
            updateRewardInternal(distributionStorage, accountStorage, rewarded, reward, 0, false);

            distributionStorage.totalEligible += currentAccountBalance;

            emit RewardEnabled(msgSender, rewarded, reward);
        }
    }

    /// @notice Disable reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function disableReward(address rewarded, address reward, bool forfeitRecentReward) external virtual override {
        address msgSender = _msgSender();
        AccountStorage storage accountStorage = accounts[msgSender][rewarded];
        if (accountStorage.enabledRewards.remove(reward)) {
            DistributionStorage storage distributionStorage = distributions[rewarded][reward];
            uint256 currentAccountBalance = accountStorage.balance;

            updateRewardInternal(
                distributionStorage, accountStorage, rewarded, reward, currentAccountBalance, forfeitRecentReward
            );

            distributionStorage.totalEligible -= currentAccountBalance;

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
        // If the account disables the rewards we pass an account balance of zero to not accrue any.
        AccountStorage storage accountStorage = accounts[account][rewarded];
        uint256 currentAccountBalance = accountStorage.enabledRewards.contains(reward) ? accountStorage.balance : 0;

        EarnStorage memory accountEarned = accountStorage.earned[reward];
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        (uint112 deltaAccountZero,,) =
            calculateRewards(distributionStorage, accountEarned, currentAccountBalance, forfeitRecentReward);

        // If we have spillover rewards, we add them to `address(0)`.
        if (account == address(0) && deltaAccountZero != 0) {
            return accountEarned.claimable + deltaAccountZero;
        }

        return accountEarned.claimable;
    }

    /// @notice Returns enabled reward tokens for a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return An array of addresses representing the enabled reward tokens.
    function enabledRewards(
        address account,
        address rewarded
    ) external view virtual override returns (address[] memory) {
        return accounts[account][rewarded].enabledRewards.get();
    }

    /// @notice Returns the rewarded token balance of a specific account.
    /// @param account The address of the account.
    /// @param rewarded The address of the rewarded token.
    /// @return The rewarded token balance of the account.
    function balanceOf(address account, address rewarded) external view virtual override returns (uint256) {
        return accounts[account][rewarded].balance;
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
        uint48 epoch
    ) public view virtual override returns (uint256) {
        DistributionStorage storage distributionStorage = distributions[rewarded][reward];
        return distributionStorage.amounts[epoch / EPOCHS_PER_SLOT][epoch % EPOCHS_PER_SLOT];
    }

    /// @notice Returns the total supply of the rewarded token enabled and eligible to receive the reward token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total supply of the rewarded token enabled and eligible to receive the reward token.
    function totalRewardedEligible(address rewarded, address reward) external view virtual override returns (uint256) {
        return distributions[rewarded][reward].totalEligible;
    }

    /// @notice Returns the total reward token amount registered to be distributed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount distributed for the rewarded token.
    function totalRewardRegistered(address rewarded, address reward) external view returns (uint256) {
        return distributions[rewarded][reward].totalRegistered;
    }

    /// @notice Returns the total reward token amount claimed for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @return The total reward token amount claimed for the rewarded token.
    function totalRewardClaimed(address rewarded, address reward) external view returns (uint256) {
        return distributions[rewarded][reward].totalClaimed;
    }

    /// @notice Returns the current epoch based on the block timestamp.
    /// @return The current epoch.
    function currentEpoch() public view override returns (uint48) {
        return getEpoch(uint48(block.timestamp));
    }

    /// @notice Returns the epoch for a given timestamp.
    /// @param timestamp The timestamp to get the epoch for.
    /// @return The epoch for the given timestamp.
    function getEpoch(uint48 timestamp) public view override returns (uint48) {
        return uint48(timestamp / EPOCH_DURATION);
    }

    /// @notice Returns the start timestamp for a given epoch.
    /// @param epoch The epoch to get the start timestamp for.
    /// @return The start timestamp for the given epoch.
    function getEpochStartTimestamp(uint48 epoch) public view override returns (uint48) {
        return uint48(epoch * EPOCH_DURATION);
    }

    /// @notice Returns the end timestamp for a given epoch.
    /// @dev The end timestamp is just after its epoch, and is the same as the start timestamp from the next epoch.
    /// @param epoch The epoch to get the end timestamp for.
    /// @return The end timestamp for the given epoch.
    function getEpochEndTimestamp(uint48 epoch) public view override returns (uint48) {
        return uint48(getEpochStartTimestamp(epoch) + EPOCH_DURATION);
    }

    /// @notice Increases the reward token amounts for a specific rewarded token.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param startEpoch The starting epoch to increase the reward token amount for.
    /// @param amounts The token amounts to increase by.
    function increaseRewardAmounts(
        address rewarded,
        address reward,
        uint48 startEpoch,
        uint128[] memory amounts
    ) internal virtual {
        mapping(uint256 => uint128[EPOCHS_PER_SLOT]) storage storageAmounts = distributions[rewarded][reward].amounts;

        for (uint48 i = 0; i < amounts.length; ++i) {
            // Overflow safe because `totalRegistered <= type(uint144).max / SCALER < type(uint128).max`.
            unchecked {
                uint48 epoch = startEpoch + i;
                storageAmounts[epoch / EPOCHS_PER_SLOT][epoch % EPOCHS_PER_SLOT] += amounts[i];
            }
        }
    }

    /// @notice Claims the earned reward for a specific account, rewarded token, and reward token, and transfers it to
    /// the recipient.
    /// @dev If recipient is address(0) or there is no reward to claim, this function does nothing.
    /// @param account The address of the account claiming the reward.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param recipient The address to which the claimed reward will be transferred.
    function claim(address account, address rewarded, address reward, address recipient) internal virtual {
        if (recipient == address(0)) revert InvalidRecipient();

        EarnStorage storage accountEarned = accounts[account][rewarded].earned[reward];
        uint128 amount = accountEarned.claimable;

        // If there is a reward token to claim, transfer it to the recipient and emit an event.
        if (amount != 0) {
            DistributionStorage storage distributionStorage = distributions[rewarded][reward];
            uint128 totalClaimed = distributionStorage.totalClaimed;
            uint128 newTotalClaimed = totalClaimed + amount;

            distributionStorage.totalClaimed = newTotalClaimed;
            accountEarned.claimable = 0;

            IERC20(reward).safeTransfer(recipient, amount);
            emit RewardClaimed(account, rewarded, reward, amount);
        }
    }

    /// @notice Updates the data for a specific account, rewarded token and reward token.
    /// @dev If required, this function artificially accumulates rewards for the address(0) to avoid loss of rewards
    /// that wouldn't be claimable by anyone else.
    /// @dev This function does not update total eligible amount or account balances.
    /// @param distributionStorage Pointer to the storage of the distribution.
    /// @param accountStorage Pointer to the storage of the account.
    /// @param rewarded The address of the rewarded token.
    /// @param reward The address of the reward token.
    /// @param currentAccountBalance The current rewarded token balance of the account.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    function updateRewardInternal(
        DistributionStorage storage distributionStorage,
        AccountStorage storage accountStorage,
        address rewarded,
        address reward,
        uint256 currentAccountBalance,
        bool forfeitRecentReward
    ) internal virtual {
        EarnStorage memory accountEarned = accountStorage.earned[reward];

        (uint112 deltaAccountZero, uint48 lastUpdated, uint208 accumulator) =
            calculateRewards(distributionStorage, accountEarned, currentAccountBalance, forfeitRecentReward);

        distributionStorage.lastUpdated = lastUpdated;
        distributionStorage.accumulator = accumulator;
        accountStorage.earned[reward] = accountEarned;

        // If there were excess rewards, allocate them to address(0).
        // Overflow safe because `totalRegistered <= type(uint144).max / SCALER < type(uint112).max`.
        if (deltaAccountZero != 0) {
            accounts[address(0)][rewarded].earned[reward].claimable += deltaAccountZero;
        }
    }

    /// @notice Computes updated data for a specific account, rewarded token, and reward token.
    /// @param distribution The distribution storage memory, which is modified by this function.
    /// @param accountEarned The account earned storage memory, which is modified by this function.
    /// @param currentAccountBalance The current rewarded token balance of the account.
    /// @param forfeitRecentReward Whether to forfeit the recent rewards and not update the accumulator.
    /// @return deltaAccountZero Amount to be credited to address(0) in case rewards were to be lost.
    function calculateRewards(
        DistributionStorage storage distribution,
        EarnStorage memory accountEarned,
        uint256 currentAccountBalance,
        bool forfeitRecentReward
    ) internal view virtual returns (uint112 deltaAccountZero, uint48 lastUpdated, uint208 accumulator) {
        // If the distribution is not initialized, return.
        lastUpdated = distribution.lastUpdated;
        accumulator = distribution.accumulator;
        if (lastUpdated == 0) return (0, lastUpdated, accumulator);

        if (!forfeitRecentReward) {
            // Get the start and end epochs based on the last updated timestamp of the distribution.
            uint48 epochStart = getEpoch(lastUpdated);
            uint48 epochEnd = currentEpoch() + 1;
            uint256 delta;

            // Calculate the amount of tokens since the last update that should be distributed.
            for (uint48 epoch = epochStart; epoch < epochEnd; ++epoch) {
                uint256 amount = distribution.amounts[epoch / EPOCHS_PER_SLOT][epoch % EPOCHS_PER_SLOT];
                delta += SCALER * _timeElapsedInEpoch(epoch, lastUpdated) * amount / EPOCH_DURATION;
            }

            // Increase the accumulator scaled by the total eligible amount earning reward. In case nobody earns
            // rewards, accrue them to address(0). Otherwise, some portion of the rewards might get lost.
            uint256 totalEligible = distribution.totalEligible;
            if (totalEligible == 0) {
                // Overflow safe because `totalRegistered <= type(uint144).max / SCALER < type(uint112).max`.
                deltaAccountZero = uint112(delta / SCALER);
            } else {
                // Overflow safe because `totalRegistered <= type(uint144).max / SCALER`.
                accumulator += uint144(delta / totalEligible);
            }

            // Snapshot the timestamp.
            lastUpdated = uint48(block.timestamp);
        }

        // Update the account's earned amount.
        // Overflow safe because `totalRegistered <= type(uint144).max / SCALER < type(uint112).max`.
        accountEarned.claimable +=
            uint112(uint256(accumulator - accountEarned.accumulator) * currentAccountBalance / SCALER);

        // Snapshot new accumulator value.
        // Downcasting is safe because the `total registered amount <= type(uint144).max / SCALER`.
        accountEarned.accumulator = uint144(accumulator);
    }

    /// @notice Transfers a specified amount of a token from a given address to this contract.
    /// @dev This function uses `SafeERC20.safeTransferFrom` function to move tokens.
    /// It checks the balance before and after the transfer to ensure the correct amount has been transferred.
    /// If the transferred amount does not match the expected amount, it reverts.
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

    /// @notice Calculates the time elapsed within a given epoch.
    /// @dev This function compares the current block timestamp with the start and end timestamps of the epoch.
    /// @dev If the epoch is ongoing, it calculates the time elapsed since the last update or the start of the epoch,
    /// whichever is smaller.
    /// @dev If the epoch has ended and there was an update since its start, it calculates the time elapsed since the
    /// last update to the end of the epoch.
    /// @dev If the epoch has ended and there wasn't an update since its start, it returns the epoch duration.
    /// @dev If the epoch hasn't started, then there can't be a later update yet, and we return zero.
    /// @param epoch The epoch for which to calculate the time elapsed.
    /// @param lastUpdated The timestamp of the last update.
    /// @return The time elapsed in the given epoch.
    function _timeElapsedInEpoch(uint48 epoch, uint48 lastUpdated) internal view returns (uint256) {
        // Get the start and end timestamps for the given epoch.
        uint256 startTimestamp = getEpochStartTimestamp(epoch);
        uint256 endTimestamp = getEpochEndTimestamp(epoch);

        // Calculate the time elapsed in the given epoch.
        if (block.timestamp < startTimestamp) {
            // The epoch hasn't started yet.
            return 0;
        } else if (block.timestamp >= startTimestamp && block.timestamp < endTimestamp) {
            // The epoch is ongoing.
            // If the last update was in or after the given epoch, return the time elapsed since the last update.
            // Otherwise return the time elapsed from the start of the given epoch.
            return lastUpdated > startTimestamp ? block.timestamp - lastUpdated : block.timestamp - startTimestamp;
        } else {
            // The epoch has ended.
            // If the last update was in or after the given epoch, return the time elapsed between the last update to
            // the end of the given epoch. If the last update was before the start of the given epoch, return the epoch
            // duration.
            return lastUpdated > startTimestamp ? endTimestamp - lastUpdated : EPOCH_DURATION;
        }
    }
}
