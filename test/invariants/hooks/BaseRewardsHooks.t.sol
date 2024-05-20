// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {BaseRewardStreams} from "src/BaseRewardStreams.sol";
import {BaseRewardStreamsHarness} from "test/harness/BaseRewardStreamsHarness.sol";

// Test Helpers
import {Pretty, Strings} from "../utils/Pretty.sol";

// Test Contracts
import {BaseHooks} from "../base/BaseHooks.t.sol";

import "forge-std/console.sol";

/// @title BaseRewards Before After Hooks
/// @notice Helper contract for before and after hooks
/// @dev This contract is inherited by handlers
abstract contract BaseRewardsHooks is BaseHooks {
    using Strings for string;
    using Pretty for uint256;
    using Pretty for int256;

    struct BaseRewardsVars {
        // Rewards Accounting
        uint256 totalRewardedBefore;
        uint256 totalRewardedAfter;
        // Account Storage
        uint160 accumulatorBefore;
        uint160 accumulatorAfter;
        // Distribution Storage
        uint256 lastUpdatedBefore;
        uint256 lastUpdatedAfter;
        uint256 distributionAccumulatorBefore;
        uint256 distributionAccumulatorAfter;
        uint256 totalRegisteredBefore;
        uint256 totalRegisteredAfter;
    }

    BaseRewardsVars baseRewardsVars;

    function _baseRewardsBefore(address account, address rewarded, address _reward) internal {
        // Account Storage
        BaseRewardStreams.EarnStorage memory earnStorage = target.getAccountEarnedData(account, rewarded, _reward);
        baseRewardsVars.accumulatorBefore = earnStorage.accumulator;

        // Distribution Storage
        (
            baseRewardsVars.lastUpdatedBefore,
            baseRewardsVars.distributionAccumulatorBefore,
            ,
            baseRewardsVars.totalRegisteredBefore,
        ) = target.getDistributionData(rewarded, _reward);
    }

    function _baseRewardsAfter(address account, address rewarded, address _reward) internal {
        // Account Storage
        BaseRewardStreams.EarnStorage memory earnStorage = target.getAccountEarnedData(account, rewarded, _reward);
        baseRewardsVars.accumulatorAfter = earnStorage.accumulator;

        // Distribution Storage
        (
            baseRewardsVars.lastUpdatedAfter,
            baseRewardsVars.distributionAccumulatorAfter,
            ,
            baseRewardsVars.totalRegisteredAfter,
        ) = target.getDistributionData(rewarded, _reward);
    }

    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                POST CONDITION INVARIANTS                                  //
    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       UPDATE REWARDS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_UPDATE_REWARDS_INVARIANT_A(address account, address rewarded, address _reward) internal {
        if (
            _enabledRewards(account, rewarded, address(target))
                && _distributionActive(rewarded, _reward, address(target))
        ) {
            assertEq(baseRewardsVars.lastUpdatedAfter, block.timestamp, UPDATE_REWARDS_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       DISTRIBUTION                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_DISTRIBUTION_INVARIANT_A() internal {
        assertGe(baseRewardsVars.lastUpdatedAfter, baseRewardsVars.lastUpdatedBefore, DISTRIBUTION_INVARIANT_A);
    }

    function assert_DISTRIBUTION_INVARIANT_B() internal {
        assertGe(
            baseRewardsVars.distributionAccumulatorAfter,
            baseRewardsVars.distributionAccumulatorBefore,
            DISTRIBUTION_INVARIANT_B
        );
    }

    function assert_DISTRIBUTION_INVARIANT_G(uint256 amount) internal {
        assertEq(
            baseRewardsVars.totalRegisteredAfter,
            baseRewardsVars.totalRegisteredBefore + amount,
            DISTRIBUTION_INVARIANT_G
        );
    }

    function assert_DISTRIBUTION_INVARIANT_J(address _rewarded, address _reward, address _target) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        BaseRewardStreamsHarness.EarnStorage memory earnStorage =
            target_.getAccountEarnedData(address(0), _rewarded, _reward);
        assertEq(earnStorage.claimable, 0, DISTRIBUTION_INVARIANT_J);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       ACCOUNT STORAGE                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ACCOUNT_STORAGE_INVARIANT_A() internal {
        assertGe(baseRewardsVars.accumulatorAfter, baseRewardsVars.accumulatorBefore, ACCOUNT_STORAGE_INVARIANT_A);
    }
}
