// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Handler Contracts
import {BaseRewardsHandler} from "./handlers/BaseRewardsHandler.t.sol";
import {StakingRewardStreamsHandler} from "./handlers/StakingRewardStreamsHandler.t.sol";
import {EVCHandler} from "./handlers/external/EVCHandler.t.sol";

// Simulators
import {DonationAttackHandler} from "./handlers/simulators/DonationAttackHandler.t.sol";
import {ERC20BalanceForwarderHandler} from "./handlers/simulators/ERC20BalanceForwarderHandler.t.sol";
import {ControllerHandler} from "./handlers/simulators/ControllerHandler.t.sol";

/// @notice Helper contract to aggregate all handler contracts, inherited in BaseInvariants
abstract contract HandlerAggregator is
    BaseRewardsHandler, // Module handlers
    StakingRewardStreamsHandler,
    EVCHandler, // EVC handler
    DonationAttackHandler, // Simulator handlers
    ERC20BalanceForwarderHandler,
    ControllerHandler
{
    /// @notice Helper function in case any handler requires additional setup
    function _setUpHandlers() internal {}
}
