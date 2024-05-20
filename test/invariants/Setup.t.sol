// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {EthereumVaultConnector} from "evc/EthereumVaultConnector.sol";

// Test Contracts
import {StakingRewardStreamsHarness} from "test/harness/StakingRewardStreamsHarness.sol";
import {TrackingRewardStreamsHarness} from "test/harness/TrackingRewardStreamsHarness.sol";
import {BaseTest} from "./base/BaseTest.t.sol";

// Mock Contracts
import {MockController} from "test/utils/MockController.sol";
import {MockERC20, MockERC20BalanceForwarder} from "test/utils/MockERC20.sol";

// Utils
import {Actor} from "./utils/Actor.sol";

/// @title Setup
/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal {
        // Deplopy EVC and needed contracts
        _deployProtocolCore();
    }

    function _deployProtocolCore() internal {
        // Deploy the EVC
        evc = new EthereumVaultConnector();

        // Deploy the Distributors
        stakingDistributor = new StakingRewardStreamsHarness(address(evc), 10 days);
        trackingDistributor = new TrackingRewardStreamsHarness(address(evc), 10 days);

        // Deploy assets
        stakingRewarded = address(new MockERC20("Staking Rewarded", "SRWDD"));
        trackingRewarded =
            address(new MockERC20BalanceForwarder(evc, trackingDistributor, "Tracking Rewarded", "SFRWDD"));
        reward = address(new MockERC20("Reward", "RWD"));

        assetAddresses.push(stakingRewarded);
        assetAddresses.push(trackingRewarded);
        assetAddresses.push(reward);

        // Store extra setup data
        Setup memory _setup1 = Setup({rewarded: stakingRewarded, distributor: address(stakingDistributor)});
        distributionSetups.push(_setup1);

        Setup memory _setup2 = Setup({rewarded: trackingRewarded, distributor: address(trackingDistributor)});
        distributionSetups.push(_setup2);

        // Deploy the controller
        controller = new MockController(evc);
    }

    function _setUpActors() internal {
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        address[] memory tokens = new address[](3);
        tokens[0] = stakingRewarded;
        tokens[1] = trackingRewarded;
        tokens[2] = reward;

        address[] memory callers = new address[](2);
        callers[0] = address(stakingDistributor);
        callers[1] = address(trackingDistributor);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deply actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, callers);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                MockERC20 _token = MockERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }
            actorAddresses.push(_actor);
        }
    }

    function _setUpActor(
        address userAddress,
        address[] memory tokens,
        address[] memory callers
    ) internal returns (address actorAddress) {
        bool success;
        Actor _actor = new Actor(tokens, callers);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }
}
