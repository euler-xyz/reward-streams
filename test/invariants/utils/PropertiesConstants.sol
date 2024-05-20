// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract PropertiesConstants {
    // Constant echidna addresses
    address constant USER1 = address(0x10000);
    address constant USER2 = address(0x20000);
    address constant USER3 = address(0x30000);
    uint256 constant INITIAL_BALANCE = 1000e18;

    // Protocol constants
    uint256 constant MAX_EPOCHS_AHEAD = 5;
    uint256 constant MAX_DISTRIBUTION_LENGTH = 25;

    uint48 constant MAX_EPOCHS_AHEAD_END = uint48(MAX_EPOCHS_AHEAD) + uint48(MAX_DISTRIBUTION_LENGTH);
    uint256 constant SCALER = 2e19;
}
