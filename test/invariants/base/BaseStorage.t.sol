// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {EthereumVaultConnector} from "evc/EthereumVaultConnector.sol";

// Test Contracts
import {StakingRewardStreamsHarness} from "test/harness/StakingRewardStreamsHarness.sol";
import {TrackingRewardStreamsHarness} from "test/harness/TrackingRewardStreamsHarness.sol";

// Mock Contracts
import {MockController} from "test/utils/MockController.sol";

// Utils
import {Actor} from "../utils/Actor.sol";

// Interfaces
import {BaseRewardStreamsHarness} from "test/harness/BaseRewardStreamsHarness.sol";

/// @notice BaseStorage contract for all test contracts, works in tandem with BaseTest
abstract contract BaseStorage {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       CONSTANTS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    uint256 constant MAX_TOKEN_AMOUNT = 1e29;

    uint256 constant ONE_DAY = 1 days;
    uint256 constant ONE_MONTH = ONE_YEAR / 12;
    uint256 constant ONE_YEAR = 365 days;

    uint256 internal constant NUMBER_OF_ACTORS = 3;
    uint256 internal constant INITIAL_ETH_BALANCE = 1e26;
    uint256 internal constant INITIAL_COLL_BALANCE = 1e21;

    uint256 constant VIRTUAL_DEPOSIT_AMOUNT = 1e6;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTORS                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Stores the actor during a handler call
    Actor internal actor;

    /// @notice Mapping of fuzzer user addresses to actors
    mapping(address => Actor) internal actors;

    /// @notice Array of all actor addresses
    address[] internal actorAddresses;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SUITE STORAGE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    // STAKING CONTRACTS

    /// @notice Testing targets
    StakingRewardStreamsHarness internal stakingDistributor;
    TrackingRewardStreamsHarness internal trackingDistributor;

    BaseRewardStreamsHarness internal target;

    /// @notice EVC contract
    EthereumVaultConnector internal evc;

    // ASSETS

    /// @notice mock assets
    address internal stakingRewarded;
    address internal trackingRewarded;
    address internal reward;

    /// @notice mock controller
    MockController internal controller;

    /// @notice Rewards seeder
    address seeder;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       EXTRA VARIABLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    address[] internal assetAddresses;

    struct Setup {
        address rewarded;
        address distributor;
    }

    Setup[] internal distributionSetups;
}
