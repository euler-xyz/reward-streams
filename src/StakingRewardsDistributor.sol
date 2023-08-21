// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./RewardsDistributor.sol";

contract StakingRewardsDistributor is
    IStakingRewardsDistributor,
    RewardsDistributor
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    event Staked(address indexed account, address indexed vault, uint amount);
    event Unstaked(address indexed account, address indexed vault, uint amount);

    constructor(
        ICVC cvc,
        uint40 periodDuration
    )
        RewardsDistributor(
            cvc,
            IStakingRewardsDistributor(address(0)),
            periodDuration
        )
    {}

    function enableReward(
        address vault,
        address reward
    ) external override(IRewardsDistributor, RewardsDistributor) {
        address msgSender = CVCAuthenticate();

        if (accountLookup[msgSender].enabledRewards[vault].add(reward)) {
            uint currentBalance = accountLookup[msgSender].balances[vault];
            uint currentTotal = totals[vault][reward];

            totals[vault][reward] = currentTotal + currentBalance;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                0
            );

            emit RewardEnabled(msgSender, vault, reward);
        }
    }

    function disableReward(
        address vault,
        address reward
    ) external override(IRewardsDistributor, RewardsDistributor) {
        address msgSender = CVCAuthenticate();

        if (accountLookup[msgSender].enabledRewards[vault].remove(reward)) {
            uint currentBalance = accountLookup[msgSender].balances[vault];
            uint currentTotal = totals[vault][reward];

            totals[vault][reward] = currentTotal - currentBalance;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                currentBalance
            );

            emit RewardDisabled(msgSender, vault, reward);
        }
    }

    function updateRewards(
        address account,
        address vault
    ) public override(IRewardsDistributor, RewardsDistributor) {
        address[] memory enabledRewards = accountLookup[account]
            .enabledRewards[vault]
            .values();

        if (enabledRewards.length == 0) return;

        uint currentBalance = accountLookup[account].balances[vault];

        // we need to iterate over all rewards that the account has enabled for a given vault and update the storage
        uint length = enabledRewards.length;
        for (uint i; i < length; ) {
            updateDataAndClearAmounts(
                account,
                vault,
                enabledRewards[i],
                totals[vault][enabledRewards[i]],
                currentBalance
            );

            unchecked {
                ++i;
            }
        }
    }

    function stake(address vault, uint amount) public override {
        address msgSender = CVCAuthenticate();

        if (amount == 0) revert RewardsDistributor_InvalidAmount();

        amount = amount == type(uint).max
            ? IERC20(vault).balanceOf(msgSender)
            : amount;

        uint oldBalance = IERC20(vault).balanceOf(address(this));
        IERC20(vault).safeTransferFrom(msgSender, address(this), amount);

        if (IERC20(vault).balanceOf(address(this)) - oldBalance != amount) {
            revert RewardsDistributor_InvalidAmount();
        }

        // balance must be updated after the transfer because the non-staking rewards distributor
        // may call into this contract to fetch the balance of msgSender during the transfer
        uint currentBalance = accountLookup[msgSender].balances[vault];
        accountLookup[msgSender].balances[vault] = currentBalance + amount;

        address[] memory enabledRewards = accountLookup[msgSender]
            .enabledRewards[vault]
            .values();
        uint length = enabledRewards.length;
        for (uint i; i < length; ) {
            address reward = enabledRewards[i];
            uint currentTotal = totals[vault][reward];
            totals[vault][reward] = currentTotal + amount;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                currentBalance
            );

            unchecked {
                ++i;
            }
        }

        emit Staked(msgSender, vault, amount);
    }

    function unstake(
        address vault,
        address recipient,
        uint amount
    ) public override {
        address msgSender = CVCAuthenticate();

        if (amount == 0) revert RewardsDistributor_InvalidAmount();

        amount = amount == type(uint).max
            ? accountLookup[msgSender].balances[vault]
            : amount;

        IERC20(vault).safeTransfer(recipient, amount);

        // balance must be updated after the transfer because the non-staking rewards distributor
        // may call into this contract to fetch the balance of msgSender during the transfer
        uint currentBalance = accountLookup[msgSender].balances[vault];
        accountLookup[msgSender].balances[vault] = currentBalance - amount;

        address[] memory enabledRewards = accountLookup[msgSender]
            .enabledRewards[vault]
            .values();
        uint length = enabledRewards.length;
        for (uint i; i < length; ) {
            address reward = enabledRewards[i];
            uint currentTotal = totals[vault][reward];
            totals[vault][reward] = currentTotal - amount;

            updateDataAndClearAmounts(
                msgSender,
                vault,
                reward,
                currentTotal,
                currentBalance
            );

            unchecked {
                ++i;
            }
        }

        emit Unstaked(msgSender, vault, amount);
    }
}
