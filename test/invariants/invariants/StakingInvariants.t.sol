// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

/// @title StakingInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract StakingInvariants is HandlerAggregator {
    function assert_STAKING_INVARIANT_A(address user) internal {
        assertEq(
            stakingDistributor.balanceOf(user, stakingRewarded),
            ghost_deposits[user][stakingRewarded],
            STAKING_INVARIANT_A
        );
    }

    //////////////////////////////////////////////////////////////////////////////////////////////
    //                                        HELPERS                                           //
    //////////////////////////////////////////////////////////////////////////////////////////////
}
