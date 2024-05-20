// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Invariant Contracts
import {BaseInvariants, BaseRewardStreamsHarness} from "./invariants/BaseInvariants.t.sol";
import {StakingInvariants} from "./invariants/StakingInvariants.t.sol";

/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants that inherits HandlerAggregator
abstract contract Invariants is BaseInvariants, StakingInvariants {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BASE INVARIANTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_BASE_INVARIANTS() public returns (bool) {
        for (uint256 i; i < distributionSetups.length; ++i) {
            (address rewarded, address _target) = _getSetupData(i);
            assert_BASE_INVARIANT_B(rewarded, reward, _target);
            assert_BASE_INVARIANT_E(rewarded, reward, _target);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 UPDATE REWARDS INVARIANTS                                 //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_UPDATE_REWARDS_INVARIANT() public returns (bool) {
        for (uint256 i; i < distributionSetups.length; ++i) {
            (address rewarded, address _target) = _getSetupData(i);
            assert_UPDATE_REWARDS_INVARIANT_B(rewarded, reward, _target);
            for (uint256 j; j < actorAddresses.length; ++j) {
                assert_UPDATE_REWARDS_INVARIANT_C(rewarded, reward, _target, actorAddresses[j]);
            }
            assert_UPDATE_REWARDS_INVARIANT_D(rewarded, reward, _target);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  DISTRIBUTION INVARIANTS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_DISTRIBUTION_INVARIANTS() public returns (bool) {
        for (uint256 i; i < distributionSetups.length; ++i) {
            (address rewarded, address _target) = _getSetupData(i);
            assert_DISTRIBUTION_INVARIANT_C(rewarded, reward, _target);
            assert_DISTRIBUTION_INVARIANT_D(rewarded, reward, _target);
            assert_DISTRIBUTION_INVARIANT_E(rewarded, reward, _target);
            //assert_DISTRIBUTION_INVARIANT_F(rewarded, reward, _target);

            uint256 sumRewardedBalances;
            for (uint256 j; j < actorAddresses.length; ++j) {
                if (BaseRewardStreamsHarness(_target).isRewardEnabled(actorAddresses[j], rewarded, reward)) {
                    sumRewardedBalances += BaseRewardStreamsHarness(_target).balanceOf(actorAddresses[j], rewarded);
                }
            }
            assert_DISTRIBUTION_INVARIANT_I(rewarded, reward, _target, sumRewardedBalances);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STAKING INVARIANTS                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_STAKING_INVARIANTS() public returns (bool) {
        for (uint256 i; i < actorAddresses.length; ++i) {
            assert_STAKING_INVARIANT_A(actorAddresses[i]);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        VIEW INVARIANTS                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
