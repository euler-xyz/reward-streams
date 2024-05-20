// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor, IERC20} from "../utils/Actor.sol";
import {BaseHandler} from "../base/BaseHandler.t.sol";

// Interfaces
import {IStakingRewardStreams} from "src/interfaces/IRewardStreams.sol";

import "forge-std/console.sol";

/// @title StakingRewardStreamsHandler
/// @notice Handler test contract for the BorrowingModule actions
contract StakingRewardStreamsHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    mapping(address => mapping(address => uint256)) public ghost_deposits;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function stake(uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        address _target = address(stakingDistributor);

        _setTarget(_target);

        uint256 balanceOfActorBefgore = IERC20(stakingRewarded).balanceOf(address(actor));

        _before(address(actor), stakingRewarded, reward);

        (success, returnData) =
            actor.proxy(_target, abi.encodeWithSelector(IStakingRewardStreams.stake.selector, stakingRewarded, amount));

        if (success) {
            _after(address(actor), stakingRewarded, reward);

            if (amount == type(uint256).max) {
                amount = balanceOfActorBefgore;
            }

            ghost_deposits[address(actor)][stakingRewarded] += amount;

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            assert_UPDATE_REWARDS_INVARIANT_A(address(actor), address(stakingRewarded), reward);
        }
    }

    function unstake(uint8 i, uint256 amount, bool forfeitRecentReward) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address recipient = _getRandomActor(i);

        address _target = address(stakingDistributor);

        _setTarget(_target);

        _before(address(actor), address(stakingRewarded), reward);

        (success, returnData) = actor.proxy(
            _target,
            abi.encodeWithSelector(
                IStakingRewardStreams.unstake.selector, stakingRewarded, amount, recipient, forfeitRecentReward
            )
        );

        if (success) {
            _after(address(actor), address(stakingRewarded), reward);

            ghost_deposits[address(actor)][stakingRewarded] -= amount;

            ////////////////// HANDLER SPECIFIC POSTCONDITIONS //////////////////

            // UPDATE REWARDS POSTCONDITIONS
            if (!forfeitRecentReward) {
                assert_UPDATE_REWARDS_INVARIANT_A(address(actor), address(stakingRewarded), reward);
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         OWNER ACTIONS                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
