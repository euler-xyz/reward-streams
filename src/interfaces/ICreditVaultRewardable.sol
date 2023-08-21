// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface ICreditVaultRewardable {
    function enableRewardsUpdate(address account) external;

    function disableRewardsUpdate(address account) external;
}
