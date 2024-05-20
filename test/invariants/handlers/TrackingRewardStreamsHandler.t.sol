// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Test Contracts
import {Actor} from "../utils/Actor.sol";
import {BaseHandler} from "../base/BaseHandler.t.sol";

import {MockERC20BalanceForwarder} from "test/invariants/Setup.t.sol";

/// @title  TrackingRewardStreamsHandler
/// @notice Handler test contract for ERC20 contacts
contract TrackingRewardStreamsHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_TRACKING_INVARIANT_A(uint8 i, uint256 newAccountBalance, bool forfeitRecentReward) external {
        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        try MockERC20BalanceForwarder(trackingRewarded).balanceTrackerHookSimulator(
            account, newAccountBalance, forfeitRecentReward
        ) {} catch {
            assertTrue(false, TRACKING_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
