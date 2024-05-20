// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Contracts
import {BaseRewardStreamsHarness} from "test/harness/BaseRewardStreamsHarness.sol";
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

import "forge-std/console.sol";

/// @title BaseInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract BaseInvariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_BASE_INVARIANT_B(address _rewarded, address _reward, address _target) internal {
        (uint256 totalEligible,,) = BaseRewardStreamsHarness(_target).getDistributionTotals(_rewarded, _reward);
        if (totalEligible == 0) {
            try BaseRewardStreamsHarness(_target).updateReward(_rewarded, _reward, address(0)) {}
            catch {
                assertTrue(false, BASE_INVARIANT_B);
            }
        }
    }

    function assert_BASE_INVARIANT_E(address _rewarded, address _reward, address _target) internal {
        assertGe(
            BaseRewardStreamsHarness(_target).totalRewardRegistered(_rewarded, _reward),
            BaseRewardStreamsHarness(_target).totalRewardClaimed(_rewarded, _reward),
            BASE_INVARIANT_E
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       UPDATE REWARDS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_UPDATE_REWARDS_INVARIANT_B(address _rewarded, address _reward, address _target) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        (uint48 lastUpdated,,,,) = target_.getDistributionData(_rewarded, _reward);
        assertGe(target_.currentEpoch(), target_.getEpoch(lastUpdated), UPDATE_REWARDS_INVARIANT_B);
    }

    function assert_UPDATE_REWARDS_INVARIANT_C(
        address _rewarded,
        address _reward,
        address _target,
        address _user
    ) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        BaseRewardStreamsHarness.EarnStorage memory earnStorage =
            target_.getAccountEarnedData(_user, _rewarded, _reward);
        (, uint208 accumulator,,,) = target_.getDistributionData(_rewarded, _reward);
        assertGe(accumulator, earnStorage.accumulator, UPDATE_REWARDS_INVARIANT_C);
    }

    function assert_UPDATE_REWARDS_INVARIANT_D(address _rewarded, address _reward, address _target) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        BaseRewardStreamsHarness.EarnStorage memory earnStorage =
            target_.getAccountEarnedData(address(0), _rewarded, _reward);
        assertEq(earnStorage.accumulator, 0, UPDATE_REWARDS_INVARIANT_D);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        DISTRIBUTION                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_DISTRIBUTION_INVARIANT_C(address _rewarded, address _reward, address _target) internal {
        IERC20 rewardToken = IERC20(_reward);
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        (,,, uint128 totalRegistered, uint128 totalClaimed) = target_.getDistributionData(_rewarded, _reward);
        assertGe(rewardToken.balanceOf(_target), totalRegistered - totalClaimed, DISTRIBUTION_INVARIANT_C);
    }

    function assert_DISTRIBUTION_INVARIANT_D(address _rewarded, address _reward, address _target) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        (,,,, uint128 totalClaimed) = target_.getDistributionData(_rewarded, _reward);

        assertEq(totalClaimed, ghost_claims[_target][_rewarded][_reward], DISTRIBUTION_INVARIANT_D);
    }

    function assert_DISTRIBUTION_INVARIANT_E(address rewarded, address _reward, address _target) internal {
        BaseRewardStreamsHarness target_ = BaseRewardStreamsHarness(_target);
        uint48 currentEpoch = target_.currentEpoch();
        assertEq(
            target_.getEpochData(rewarded, _reward, currentEpoch + MAX_EPOCHS_AHEAD_END), 0, DISTRIBUTION_INVARIANT_E
        );
    }

    function assert_DISTRIBUTION_INVARIANT_I(
        address _rewarded,
        address _reward,
        address _target,
        uint256 _sumBalances
    ) internal {
        assertEq(
            BaseRewardStreamsHarness(_target).totalRewardedEligible(_rewarded, _reward),
            _sumBalances,
            DISTRIBUTION_INVARIANT_I
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            VIEW                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       ACCOUNT STORAGE                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                         //
    //////////////////////////////////////////////////////////////////////////////////////////////

    function _getTotalAmountAcrossEpochs(
        address _rewarded,
        address _reward,
        BaseRewardStreamsHarness _target
    ) internal view returns (uint256 totalAmountAcrossEpochs) {
        (uint48 lastUpdated,,,,) = _target.getDistributionData(_rewarded, _reward);

        uint48 startEpoch = _target.getEpoch(lastUpdated);
        uint48 endEpoch = _target.currentEpoch() + MAX_EPOCHS_AHEAD_END;

        for (uint48 i = startEpoch; i <= endEpoch; i++) {
            totalAmountAcrossEpochs += _target.getEpochData(_rewarded, _reward, i);
        }
    }
}
