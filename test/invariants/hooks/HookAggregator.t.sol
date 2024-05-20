// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Hook Contracts
import {BaseRewardsHooks} from "./BaseRewardsHooks.t.sol";

/// @title HookAggregator
/// @notice Helper contract to aggregate all before / after hook contracts, inherited on each handler
abstract contract HookAggregator is BaseRewardsHooks {
    /// @notice Modular hook selector, per module
    function _before(address account, address rewarded, address _reward) internal {
        _baseRewardsBefore(account, rewarded, _reward);
    }

    /// @notice Modular hook selector, per module
    function _after(address account, address rewarded, address _reward) internal {
        _baseRewardsAfter(account, rewarded, _reward);

        // Postconditions
        _checkPostConditions();
    }

    /// @notice Global Postconditions for the handlers
    /// @dev This function is called after each "hooked" action to check the postconditions
    /// @dev Individual postconditions are checked in the respective handler functions
    function _checkPostConditions() internal {
        // Distribution Postconditions
        assert_DISTRIBUTION_INVARIANT_A();
        assert_DISTRIBUTION_INVARIANT_B();

        // Account Storage Postconditions
        assert_ACCOUNT_STORAGE_INVARIANT_A();
    }
}
