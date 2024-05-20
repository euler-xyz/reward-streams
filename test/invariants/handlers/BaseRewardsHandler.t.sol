// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";

// Test Contracts
import {Actor} from "../utils/Actor.sol";
import {BaseHandler} from "../base/BaseHandler.t.sol";
import {BaseRewardStreamsHarness} from "test/harness/BaseRewardStreamsHarness.sol";

// Interfaces
import {IRewardStreams} from "src/interfaces/IRewardStreams.sol";

import "forge-std/console.sol";

/// @title BaseRewardsHandler
/// @notice Handler test contract for the risk balance forwarder module actions
contract BaseRewardsHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    mapping(address target => mapping(address rewarded => mapping(address reward => uint256))) public ghost_claims;

    mapping(address target => uint256) public ghost_addressZeroClaimedRewards;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function registerReward(uint8 i, uint48 startEpoch, uint128[] calldata rewardAmounts) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(i);

        uint256 rewardBalanceBefore = IERC20(reward).balanceOf(address(actor));

        _before(address(actor), _rewarded, reward);

        (success, returnData) = actor.proxy(
            _target,
            abi.encodeWithSelector(IRewardStreams.registerReward.selector, _rewarded, reward, startEpoch, rewardAmounts)
        );

        if (success) {
            _after(address(actor), _rewarded, reward);

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // BASE POSTCONDITIONS
            assertLe(rewardAmounts.length, MAX_DISTRIBUTION_LENGTH, BASE_INVARIANT_C);
            assertLe(startEpoch, target.currentEpoch() + MAX_EPOCHS_AHEAD, BASE_INVARIANT_D);

            if (startEpoch != 0) {
                assertGe(startEpoch, target.currentEpoch(), BASE_INVARIANT_F);
            }

            // DISTRIBUTION POSTCONDITIONS
            uint256 totalAmount = _sumRewardAmounts(rewardAmounts);
            assert_DISTRIBUTION_INVARIANT_G(totalAmount);
            assertEq(
                rewardBalanceBefore - IERC20(reward).balanceOf(address(actor)), totalAmount, DISTRIBUTION_INVARIANT_H
            );

            // UPDATE REWARDS POSTCONDITIONS
            assert_UPDATE_REWARDS_INVARIANT_A(address(actor), _rewarded, reward);
        }
    }

    function updateReward(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(i);

        _before(address(actor), _rewarded, reward);

        (success, returnData) = actor.proxy(
            _target, abi.encodeWithSelector(IRewardStreams.updateReward.selector, _rewarded, reward, address(0))
        );

        if (success) {
            _after(address(actor), _rewarded, reward);

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            assert_UPDATE_REWARDS_INVARIANT_A(address(actor), _rewarded, reward);
        }
    }

    function claimReward(uint8 i, uint8 j, bool forfeitRecentReward) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address recipient = _getRandomActor(i);

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(j);

        uint256 earnedReward = target.earnedReward(address(actor), _rewarded, reward, forfeitRecentReward);

        _before(address(actor), _rewarded, reward);

        (success, returnData) = actor.proxy(
            _target,
            abi.encodeWithSelector(
                IRewardStreams.claimReward.selector, _rewarded, reward, recipient, forfeitRecentReward
            )
        );

        if (success) {
            _after(address(actor), _rewarded, reward);

            ghost_claims[_target][_rewarded][reward] += earnedReward;

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            if (!forfeitRecentReward) {
                assert_UPDATE_REWARDS_INVARIANT_A(address(actor), _rewarded, reward);
            }
        }
    }

    function claimSpilloverReward(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address recipient = _getRandomActor(i);

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(j);

        uint256 spilloverReward = target.earnedReward(address(0), _rewarded, reward, false);

        _before(address(actor), _rewarded, reward);

        (success, returnData) = actor.proxy(
            _target, abi.encodeWithSelector(IRewardStreams.updateReward.selector, _rewarded, reward, recipient)
        );

        if (success) {
            _after(address(actor), _rewarded, reward);

            ghost_claims[_target][_rewarded][reward] += spilloverReward;

            ghost_addressZeroClaimedRewards[_target] += spilloverReward;

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////
            assert_DISTRIBUTION_INVARIANT_J(_rewarded, reward, _target);
        }
    }

    function enableReward(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(i);

        _before(address(actor), _rewarded, reward);

        (success, returnData) =
            actor.proxy(_target, abi.encodeWithSelector(IRewardStreams.enableReward.selector, _rewarded, reward));

        if (success) {
            _after(address(actor), _rewarded, reward);

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            if (!target.isRewardEnabled(address(actor), _rewarded, reward)) {
                assert_UPDATE_REWARDS_INVARIANT_A(address(actor), _rewarded, reward);
            }
        }
    }

    function disableReward(uint8 i, bool forfeitRecentReward) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the two setups randomly
        (address _rewarded, address _target) = _getRandomRewards(i);

        bool enabledBefore = _enabledRewards(address(actor), _rewarded, address(target));

        _before(address(actor), _rewarded, reward);

        (success, returnData) = actor.proxy(
            _target,
            abi.encodeWithSelector(IRewardStreams.disableReward.selector, _rewarded, reward, forfeitRecentReward)
        );

        if (success) {
            _after(address(actor), _rewarded, reward);

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            if (!forfeitRecentReward && enabledBefore && _distributionActive(_rewarded, reward, address(target))) {
                assertEq(baseRewardsVars.lastUpdatedAfter, block.timestamp, UPDATE_REWARDS_INVARIANT_A);
            }
        }
    }
}
