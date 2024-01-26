// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

/// @title IBalanceForwarder
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This interface defines the functions for enabling and disabling balance forwarding.
interface IBalanceForwarder {
    /// @notice Enables balance forwarding for the msg.sender
    /// @dev Only the msg.sender can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarding() external;

    /// @notice Disables balance forwarding for the msg.sender
    /// @dev Only the msg.sender can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarding() external;
}
