// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin/utils/structs/EnumerableSet.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "euler-cvc/interfaces/ICreditVaultConnector.sol";
import "./interfaces/IRewardsDistributors.sol";
import "./interfaces/ICreditVaultRewardable.sol";

contract NonStakingRewardsDistributor is IRewardsDistributor {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct DistributionInfo {
        uint40 lastUpdated;
        uint160 accumulator;
    }

    struct RewardInfo {
        uint96 earned;
        uint160 accumulator;
    }

    struct Account {
        mapping(address vault => uint) balances;
        mapping(address vault => EnumerableSet.AddressSet rewardsSet) enabledRewards;
        mapping(address vault => mapping(address reward => RewardInfo)) rewardLookup;
    }

    struct Amounts {
        uint128 evenEpochAmount;
        uint128 oddEpochAmount;
    }

    event RewardRegistered(
        address indexed vault,
        address indexed reward,
        uint startEpoch,
        uint128[] amounts
    );
    event RewardEnabled(
        address indexed account,
        address indexed vault,
        address indexed reward
    );
    event RewardDisabled(
        address indexed account,
        address indexed vault,
        address indexed reward
    );
    event RewardClaimed(
        address indexed account,
        address indexed vault,
        address indexed reward,
        uint amount
    );

    error RewardsDistributor_InvalidEpoch();
    error RewardsDistributor_InvalidAmount();
    error RewardsDistributor_AccumulatorOverflow();

    ICVC public immutable CVC;
    IStakingRewardsDistributor public immutable SRD;
    uint40 public immutable EPOCH_DURATION;

    mapping(address vault => mapping(address reward => mapping(uint evenEpoch => Amounts)))
        internal distributionAmounts;

    mapping(address vault => mapping(address reward => DistributionInfo))
        internal distributionLookup;

    mapping(address vault => mapping(address reward => uint)) internal totals;
    mapping(address account => Account) internal accountLookup;

    constructor(
        ICVC cvc,
        IStakingRewardsDistributor stakingRewardsDistributor,
        uint40 epochDuration
    ) {
        if (epochDuration < 7 days) {
            revert RewardsDistributor_InvalidEpoch();
        }

        CVC = cvc;
        SRD = stakingRewardsDistributor;
        EPOCH_DURATION = epochDuration;
    }

    function registerReward(
        address vault,
        address reward,
        uint40 startEpoch,
        uint128[] calldata amounts
    ) external virtual override {
        address msgSender = CVCAuthenticate();
        uint40 epoch = currentEpoch();

        if (startEpoch == 0) startEpoch = epoch + 1;

        // should be at most 5 epochs in the future
        if (!(startEpoch > epoch && startEpoch < epoch + 5)) {
            revert RewardsDistributor_InvalidEpoch();
        }

        // should be at least 1 and at most 25 epochs
        if (!(amounts.length > 0 && amounts.length <= 25)) {
            revert RewardsDistributor_InvalidAmount();
        }

        if (distributionLookup[vault][reward].lastUpdated == 0) {
            distributionLookup[vault][reward] = DistributionInfo({
                lastUpdated: uint40(block.timestamp),
                accumulator: 0
            });
        } else {
            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                totals[vault][reward],
                accountLookup[msgSender].balances[vault]
            );
        }

        uint totalAmount = storeAmounts(vault, reward, startEpoch, amounts);
        if (totalAmount == 0) revert RewardsDistributor_InvalidAmount();

        // estimate the accumulator delta between now and the start epoch to assure that the accumulator doesn't overflow.
        // for that, get to be distributed amount between now and the start epoch
        uint toBeDistributedAmount;
        {
            Amounts memory toBeDistributedAmounts;
            for (uint40 i = epoch; i <= startEpoch; ) {
                // read the amounts storage slot only every other epoch
                if (i % 2 == 0 || i == epoch) {
                    toBeDistributedAmounts = distributionAmounts[vault][reward][
                        storageIndexForEpoch(i)
                    ];
                }

                toBeDistributedAmount = i % 2 == 0
                    ? toBeDistributedAmount +
                        toBeDistributedAmounts.evenEpochAmount
                    : toBeDistributedAmount +
                        toBeDistributedAmounts.oddEpochAmount;

                unchecked {
                    ++i;
                }
            }
        }

        // sanity check for overflow (assumes supply of 1 which is a worst case scenario)
        if (
            distributionLookup[vault][reward].accumulator +
                1e18 *
                (startEpoch - epoch + amounts.length) *
                (toBeDistributedAmount + totalAmount) >=
            type(uint160).max
        ) {
            revert RewardsDistributor_AccumulatorOverflow();
        }

        uint oldBalance = IERC20(reward).balanceOf(address(this));
        IERC20(reward).safeTransferFrom(msgSender, address(this), totalAmount);

        if (
            IERC20(reward).balanceOf(address(this)) - oldBalance != totalAmount
        ) {
            revert RewardsDistributor_InvalidAmount();
        }

        emit RewardRegistered(vault, reward, startEpoch, amounts);
    }

    function enableReward(
        address vault,
        address reward
    ) external virtual override {
        address msgSender = CVCAuthenticate();

        if (accountLookup[msgSender].enabledRewards[vault].add(reward)) {
            uint currentBalance = IERC20(vault).balanceOf(msgSender);

            if (address(SRD) != address(0)) {
                currentBalance =
                    currentBalance +
                    SRD.balanceOf(msgSender, vault);
            }

            uint currentTotal = totals[vault][reward];

            accountLookup[msgSender].balances[vault] = currentBalance;
            totals[vault][reward] = currentTotal + currentBalance;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                0
            );

            if (accountLookup[msgSender].enabledRewards[vault].length() == 1) {
                ICreditVaultRewardable(vault).enableRewardsUpdate(msgSender);
            }

            emit RewardEnabled(msgSender, vault, reward);
        }
    }

    function disableReward(
        address vault,
        address reward
    ) external virtual override {
        address msgSender = CVCAuthenticate();

        if (accountLookup[msgSender].enabledRewards[vault].remove(reward)) {
            uint currentBalance = accountLookup[msgSender].balances[vault];
            uint currentTotal = totals[vault][reward];

            accountLookup[msgSender].balances[vault] = 0;
            totals[vault][reward] = currentTotal - currentBalance;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                currentBalance
            );

            if (accountLookup[msgSender].enabledRewards[vault].length() == 0) {
                ICreditVaultRewardable(vault).disableRewardsUpdate(msgSender);
            }

            emit RewardDisabled(msgSender, vault, reward);
        }
    }

    function updateRewards(
        address account,
        address vault
    ) public virtual override {
        address[] memory enabledRewards = accountLookup[account]
            .enabledRewards[vault]
            .values();

        if (enabledRewards.length == 0) return;

        uint previousBalance = accountLookup[account].balances[vault];
        uint currentBalance = IERC20(vault).balanceOf(account);

        if (address(SRD) != address(0)) {
            currentBalance = currentBalance + SRD.balanceOf(account, vault);
        }

        accountLookup[account].balances[vault] = currentBalance;

        // we need to iterate over all rewards that the account has enabled for a given vault and update the storage
        uint length = enabledRewards.length;
        for (uint i; i < length; ) {
            address reward = enabledRewards[i];
            uint currentTotal = currentBalance > previousBalance
                ? totals[vault][reward] + (currentBalance - previousBalance)
                : totals[vault][reward] - (previousBalance - currentBalance);

            totals[vault][reward] = currentTotal;

            updateDataAndClearAmounts(
                account,
                vault,
                reward,
                currentTotal,
                currentBalance
            );

            unchecked {
                ++i;
            }
        }
    }

    function claimRewards(
        address vault,
        address[] calldata rewards,
        address recipient
    ) external virtual override {
        address msgSender = CVCAuthenticate();

        updateRewards(msgSender, vault);

        address[] memory rewardsToClaim = rewards.length == 0
            ? accountLookup[msgSender].enabledRewards[vault].values()
            : rewards;

        uint rewardsLength = rewardsToClaim.length;
        for (uint i; i < rewardsLength; ) {
            address reward = rewardsToClaim[i];
            RewardInfo memory accountReward = accountLookup[msgSender]
                .rewardLookup[vault][reward];

            if (accountReward.earned > 0) {
                accountLookup[msgSender].rewardLookup[vault][reward].earned = 0;

                IERC20(reward).safeTransfer(recipient, accountReward.earned);

                emit RewardClaimed(
                    msgSender,
                    vault,
                    reward,
                    accountReward.earned
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    function rewardsEnabled(
        address account,
        address vault
    ) external view override returns (address[] memory) {
        return accountLookup[account].enabledRewards[vault].values();
    }

    function earned(
        address account,
        address vault
    )
        external
        view
        virtual
        override
        returns (address[] memory enabledRewards, uint[] memory earnedRewards)
    {
        enabledRewards = accountLookup[account].enabledRewards[vault].values();
        earnedRewards = new uint[](
            accountLookup[account].enabledRewards[vault].length()
        );

        uint currentBalance = accountLookup[account].balances[vault];
        uint length = enabledRewards.length;
        for (uint i; i < length; ) {
            address reward = enabledRewards[i];
            (, RewardInfo memory accountReward, ) = getUpdateData(
                account,
                vault,
                reward,
                totals[vault][reward],
                currentBalance
            );

            earnedRewards[i] = accountReward.earned;

            unchecked {
                ++i;
            }
        }
    }

    function balanceOf(
        address account,
        address vault
    ) external view override returns (uint) {
        return accountLookup[account].balances[vault];
    }

    function totalSupply(
        address vault,
        address reward
    ) external view override returns (uint) {
        return totals[vault][reward];
    }

    function rewardRate(
        address vault,
        address reward
    ) public view override returns (uint) {
        return rewardRate(vault, reward, currentEpoch());
    }

    function rewardRate(
        address vault,
        address reward,
        uint40 epoch
    ) public view override returns (uint) {
        Amounts memory amounts = distributionAmounts[vault][reward][
            storageIndexForEpoch(epoch)
        ];

        return
            epoch % 2 == 0 ? amounts.evenEpochAmount : amounts.oddEpochAmount;
    }

    function totalSupplies(
        address vault,
        address[] memory reward
    ) external view override returns (uint[] memory) {
        uint length = reward.length;
        uint[] memory result = new uint[](length);
        for (uint i; i < length; ) {
            result[i] = totals[vault][reward[i]];
            unchecked {
                ++i;
            }
        }
        return result;
    }

    function rewardRates(
        address vault,
        address[] memory reward
    ) external view override returns (uint[] memory) {
        uint length = reward.length;
        uint[] memory result = new uint[](length);
        for (uint i; i < length; ) {
            result[i] = rewardRate(vault, reward[i]);
            unchecked {
                ++i;
            }
        }
        return result;
    }

    function rewardRates(
        address vault,
        address[] memory reward,
        uint40 epoch
    ) external view override returns (uint[] memory) {
        uint length = reward.length;
        uint[] memory result = new uint[](length);
        for (uint i; i < length; ) {
            result[i] = rewardRate(vault, reward[i], epoch);
            unchecked {
                ++i;
            }
        }
        return result;
    }

    function currentEpoch() public view override returns (uint40) {
        return getEpoch(uint40(block.timestamp));
    }

    function getEpoch(uint40 timestamp) public view override returns (uint40) {
        return timestamp / EPOCH_DURATION;
    }

    function getEpochStartTimestamp(
        uint40 epoch
    ) public view override returns (uint40) {
        return epoch * EPOCH_DURATION;
    }

    function getEpochEndTimestamp(
        uint40 epoch
    ) public view override returns (uint40) {
        return getEpochStartTimestamp(epoch) + EPOCH_DURATION;
    }

    function storeAmounts(
        address vault,
        address reward,
        uint40 startEpoch,
        uint128[] calldata amounts
    ) internal returns (uint totalAmount) {
        uint endEpoch = startEpoch + amounts.length - 1;
        uint endIndex = storageIndexForEpoch(uint40(endEpoch));
        
        uint amountsIndex = 0;
        for (uint40 i = storageIndexForEpoch(startEpoch); i <= endIndex; ) {
            Amounts memory currentAmounts = distributionAmounts[vault][reward][i];
            Amounts memory newAmounts = Amounts({
                evenEpochAmount: currentAmounts.evenEpochAmount,
                oddEpochAmount: currentAmounts.oddEpochAmount
            });

            // assign amounts to the correct fields based on the epoch
            if (2 * i == startEpoch + amountsIndex && amountsIndex < amounts.length) {
                newAmounts.evenEpochAmount += amounts[amountsIndex++];
            }

            if (2 * i + 1 == startEpoch + amountsIndex && amountsIndex < amounts.length) {
                newAmounts.oddEpochAmount += amounts[amountsIndex++];
            }

            totalAmount =
                totalAmount +
                newAmounts.evenEpochAmount +
                newAmounts.oddEpochAmount -
                (currentAmounts.evenEpochAmount +
                    currentAmounts.oddEpochAmount);

            distributionAmounts[vault][reward][i] = newAmounts;

            unchecked {
                ++i;
            }
        }
    }

    function updateDataAndClearAmounts(
        address account,
        address vault,
        address reward,
        uint currentTotal,
        uint currentUserBalance
    ) internal virtual {
        uint[] memory amountsIndicesToClear;
        (
            distributionLookup[vault][reward],
            accountLookup[account].rewardLookup[vault][reward],
            amountsIndicesToClear
        ) = getUpdateData(
            account,
            vault,
            reward,
            currentTotal,
            currentUserBalance
        );

        uint length = amountsIndicesToClear.length;
        for (uint i; i < length; ) {
            uint index = amountsIndicesToClear[i];

            if (index == 0) break;
            else delete distributionAmounts[vault][reward][index];

            unchecked {
                ++i;
            }
        }
    }

    function getUpdateData(
        address account,
        address vault,
        address reward,
        uint currentTotal,
        uint currentUserBalance
    )
        internal
        view
        virtual
        returns (
            DistributionInfo memory distribution,
            RewardInfo memory accountReward,
            uint[] memory amountsIndicesToClear
        )
    {
        distribution = distributionLookup[vault][reward];
        accountReward = accountLookup[account].rewardLookup[vault][reward];

        if (distribution.lastUpdated != 0) {
            uint40 epochStart = getEpoch(distribution.lastUpdated);
            uint40 epochEnd = currentEpoch();
            amountsIndicesToClear = new uint[](
                (epochEnd - epochStart + 1) / 2 + 1
            );
            uint amountsIndicesToClearIndex;
            uint accumulatorDelta;
            Amounts memory amounts;
            for (uint40 i = epochStart; i <= epochEnd; ) {
                uint storageIndex = storageIndexForEpoch(i);

                // read the amounts storage slot only every other epoch
                if (i % 2 == 0 || i == epochStart) {
                    amounts = distributionAmounts[vault][reward][storageIndex];
                }

                // retrieve the amount of rewards for the given epoch
                uint epochAmount = i % 2 == 0
                    ? amounts.evenEpochAmount
                    : amounts.oddEpochAmount;

                // get given epoch's bounds
                uint epochStartTimestamp = getEpochStartTimestamp(i);
                uint epochEndTimestamp = getEpochEndTimestamp(i);

                // calculate the time elapsed in the given epoch
                uint timeElapsed;
                if (
                    block.timestamp >= epochStartTimestamp &&
                    block.timestamp < epochEndTimestamp
                ) {
                    // if the epoch is still ongoing
                    timeElapsed = distribution.lastUpdated > epochStartTimestamp
                        ? block.timestamp - distribution.lastUpdated
                        : block.timestamp - epochStartTimestamp;
                } else {
                    // if the epoch has ended
                    timeElapsed = distribution.lastUpdated > epochStartTimestamp
                        ? epochEndTimestamp - distribution.lastUpdated
                        : EPOCH_DURATION;

                    // if the odd epoch is already over, keep the storage index so that it's cleared for the gas refund
                    if (i % 2 == 1) {
                        amountsIndicesToClear[
                            amountsIndicesToClearIndex
                        ] = storageIndex;

                        unchecked {
                            ++amountsIndicesToClearIndex;
                        }
                    }
                }

                accumulatorDelta = currentTotal == 0
                    ? 0
                    : accumulatorDelta +
                        (1e18 * timeElapsed * epochAmount) /
                        EPOCH_DURATION /
                        currentTotal;

                unchecked {
                    ++i;
                }
            }

            uint accumulator = distribution.accumulator + accumulatorDelta;

            distribution.accumulator = accumulator > type(uint160).max
                ? type(uint160).max
                : uint160(accumulator);

            distribution.lastUpdated = uint40(block.timestamp);
        }

        uint amountEarned = accountReward.earned +
            (currentUserBalance *
                (distribution.accumulator - accountReward.accumulator)) /
            1e18;

        accountReward.earned = amountEarned > type(uint96).max
            ? type(uint96).max
            : uint96(amountEarned);

        accountReward.accumulator = distribution.accumulator;
    }

    function CVCAuthenticate()
        internal
        view
        virtual
        returns (address msgSender)
    {
        msgSender = msg.sender;

        if (msgSender == address(CVC)) {
            (ICVC.ExecutionContext memory context, ) = CVC.getExecutionContext(address(0));

            msgSender = context.onBehalfOfAccount;
        }
    }

    function storageIndexForEpoch(uint40 epoch) internal pure returns (uint40) {
        return epoch / 2;
    }
}
