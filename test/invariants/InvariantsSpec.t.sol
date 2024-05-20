// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title InvariantsSpec
/// @notice Invariants specification for the protocol
/// @dev Contains pseudo code and description for the invariants in the protocol
abstract contract InvariantsSpec {
    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                      PROPERTY TYPES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev On this invariant testing framework there exists two types of Properties:

    - INVARIANTS (INV): 
        - These are properties that should always hold true in the system. 
        - They are implemented under /invariants folder.

    - POSTCONDITIONS:
        - These are properties that should hold true after an action is executed.
        - They are implemented under /hooks and /handlers.

        - There exists two types of POSTCONDITIONS:
            - GLOBAL POSTCONDITIONS (GPOST): 
                - These are properties that should always hold true after an action is executed.
                - They are checked in `_checkPostConditions` function in the HookAggregator contract.
                
            - HANDLER SPECIFIC POSTCONDITIONS (HSPOST): 
    //          - These are properties that should hold true after an specific action is executed in a specific context.
                - They are implemented on each handler function under HANDLER SPECIFIC POSTCONDITIONS comment.

    The following list of system prooperties have a comment indicating the type of property they are therefore making it 
    easier to identify their implementations in the system (INV, GPOST, HSPOST): 

    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // HSPOST
    string constant BASE_INVARIANT_A =
        "BASE_INVARIANT_A: forfeitRecentRewards == true => rewards should be always cheaply enabled / disabled";
    // INV
    string constant BASE_INVARIANT_B =
        "BASE_INVARIANT_B: in case nobody is earning rewards, at least someone can claim them";
    // HSPOST
    string constant BASE_INVARIANT_C =
        "BASE_INVARIANT_C: distribution stream should be at most MAX_DISTRIBUTION_LENGTH epochs long";
    // HSPOST
    string constant BASE_INVARIANT_D =
        "BASE_INVARIANT_D: startEpoch should be at most MAX_EPOCHS_AHEAD epochs in the future";
    // INV
    string constant BASE_INVARIANT_E =
        "BASE_INVARIANT_E: totalRegistered of a distribution should always be greater than totalClaimed";
    // HSPOST
    string constant BASE_INVARIANT_F = "BASE_INVARIANT_F: startEpoch should always be 0 or greater than currentEpoch";
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       UPDATE REWARDS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // HSPOST
    string constant UPDATE_REWARDS_INVARIANT_A =
        "UPDATE_REWARDS_INVARIANT_A: after any interaction requiring reward updates updateReward should be called";
    // INV
    string constant UPDATE_REWARDS_INVARIANT_B = "UPDATE_REWARDS_INVARIANT_B: current epoch >= lastUpdated epoch";
    // INV
    string constant UPDATE_REWARDS_INVARIANT_C = "UPDATE_REWARDS_INVARIANT_C: global accumulator >= user accumulator";
    // INV
    string constant UPDATE_REWARDS_INVARIANT_D =
        "UPDATE_REWARDS_INVARIANT_D: zeroAddress account accumulator should always be 0";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       DISTRIBUTION                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // GPOST
    string constant DISTRIBUTION_INVARIANT_A =
        "DISTRIBUTION_INVARIANT_A: lastUpdated of a distribution increases monotonically";
    // GPOST
    string constant DISTRIBUTION_INVARIANT_B =
        "DISTRIBUTION_INVARIANT_B: accumulator of a distribution increases monotonically";
    //INV
    string constant DISTRIBUTION_INVARIANT_C =
        "DISTRIBUTION_INVARIANT_C: reward token amount on the contract should be greater or equal than totalRegisteres minus totalClaimed";
    //INV
    string constant DISTRIBUTION_INVARIANT_D =
        "DISTRIBUTION_INVARIANT_D: totalClaimed of a distribution should equal the amount transferred out";
    //INV
    string constant DISTRIBUTION_INVARIANT_E =
        "DISTRIBUTION_INVARIANT_E: the number of epochs of a distribution should be between bounds";
    // HSPOST
    string constant DISTRIBUTION_INVARIANT_G =
        "DISTRIBUTION_INVARIANT_G: after registerReward is called storageAmounts are updated correctly";
    // HSPOST
    string constant DISTRIBUTION_INVARIANT_H =
        "DISTRIBUTION_INVARIANT_H: after registerReward is called the correct amount of tokens is transferred in";
    // INV
    string constant DISTRIBUTION_INVARIANT_I =
        "DISTRIBUTION_INVARIANT_I: totalEligible should equal the sum of rewarded balance of all the active accounts";
    // HSPOST
    string constant DISTRIBUTION_INVARIANT_J =
        "DISTRIBUTION_INVARIANT_J: after calling claimSpilloverReward spill over claimable rewards are set to 0";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       ACCOUNT STORAGE                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // GPOST
    string constant ACCOUNT_STORAGE_INVARIANT_A =
        "ACCOUNT_STORAGE_INVARIANT_A: earn storage accumulator should increase monotonically";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         STAKING                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // INV
    string constant STAKING_INVARIANT_A = "STAKING_INVARIANT_A: user balance must always equal the sum of user deposits";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         TRACKING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // HSPOST
    string constant TRACKING_INVARIANT_A = "TRACKING_INVARIANT_A: balanceTrackerHook can never revert";

    string constant TRACKING_INVARIANT_B =
        "TRACKING_INVARIANT_B: forfeitRecentRewards is enough to prevent DOS on liquidation flow";

    string constant TRACKING_INVARIANT_C =
        "TRACKING_INVARIANT_C: calling balanceTrackerHook multiple times with the same balance does not affect the distributor";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            VIEW                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // INV
    string constant VIEW_INVARIANT_A = "VIEW_INVARIANT_A: timeElapsedInEpoch cannot revert";
}
