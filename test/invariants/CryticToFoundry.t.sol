// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Test Contracts
import {Invariants} from "./Invariants.t.sol";
import {Setup} from "./Setup.t.sol";

/// @title CryticToFoundry
/// @notice Foundry wrapper for fuzzer failed call sequences
/// @dev Regression testing for failed call sequences
contract CryticToFoundry is Invariants, Setup {
    modifier setup() override {
        _;
    }

    /// @dev Foundry compatibility faster setup debugging
    function setUp() public {
        // Deploy protocol contracts and protocol actors
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        actor = actors[USER1];
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     INVARIANTS REPLAY                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_enableReward() public {
        // 1
        this.enableReward(0);
        // 2
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 1;
        this.registerReward(0, 0, rewards);
        // 3
        _delay(1);
        this.enableReward(0);
    }

    function test_claimSpilloverReward1() public {
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 1;
        this.registerReward(0, 0, rewards);
        this.enableReward(0);
        _delay(1);
        this.claimSpilloverReward(0, 0);
    }

    function test_claimRewards1() public {
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 1;
        this.enableReward(0);
        this.registerReward(0, 0, rewards);
        _delay(1);
        this.claimReward(0, 0, true);
    }

    function test_unstake1() public {
        this.stake(115792089237316195423570985008687907853269984665640564039457584007913129639935);
        this.enableReward(0);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 77139;
        this.registerReward(0, 0, rewards);
        _delay(1);
        this.unstake(0, 1, true);
    }

    function test_disableReward1() public {
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 228074428775375066;
        this.registerReward(0, 0, rewards);
        this.enableReward(0);
        _delay(1);
        this.disableReward(0, true);
    }

    function test_STAKING_INVARIANT_A1() public {
        this.stake(115792089237316195423570985008687907853269984665640564039457584007913129639935);
        echidna_STAKING_INVARIANTS();
    }

    function test_BASE_INVARIANTS() public {
        echidna_BASE_INVARIANTS();
    }

    function test_DISTRIBUTION_INVARIANTS1() public {
        this.stake(115792089237316195423570985008687907853269984665640564039457584007913129639935);
        this.enableReward(0);
        echidna_DISTRIBUTION_INVARIANTS();
    }

    function test_DISTRIBUTION_INVARIANTS2() public {
        this.stake(20232243);
        echidna_DISTRIBUTION_INVARIANTS();
    }

    function test_DISTRIBUTION_INVARIANTS3() public {
        vm.warp(187403);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 66;
        this.registerReward(0, 0, rewards);
        _delay(8 days);
        this.enableReward(0);
        this.claimSpilloverReward(0, 0);
        echidna_DISTRIBUTION_INVARIANTS();
    }

    function test_DISTRIBUTION_INVARIANTS4() public {
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 1390;
        this.registerReward(0, 0, rewards);
        _delay(128780);
        this.enableReward(0);
        _delay(240075);
        this.stake(2623374470054327805470411115388864044445339010392982102470475852441352);
        _delay(490635);
        this.unstake(0, 0, false);
        _delay(1292434);
        rewards[0] = 1;
        this.registerReward(0, 0, rewards);
        echidna_DISTRIBUTION_INVARIANTS();
    }

    function test_DISTRIBUTION_INVARIANTS5() public {
        this.stake(1);
        _delay(130498);
        this.enableReward(0);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 2;
        this.registerReward(0, 0, rewards);
        _delay(163951 + 169761 + 1006652);
        echidna_DISTRIBUTION_INVARIANTS();
        this.claimReward(0, 0, false);
        echidna_DISTRIBUTION_INVARIANTS();
    }

    function test_UPDATE_REWARDS_INVARIANTS1() public {
        this.stake(1);
        _delay(127715);
        this.enableReward(0);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 2;
        this.registerReward(0, 0, rewards);
        _delay(163951 + 168054 + 1916652);
        echidna_UPDATE_REWARDS_INVARIANT();
        this.claimReward(0, 0, false);
        echidna_UPDATE_REWARDS_INVARIANT();
    }

    function test_UPDATE_REWARDS_INVARIANTS2() public {
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );
        this.stake(1);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 2;
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );

        this.registerReward(0, 0, rewards);
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );

        _delay(290782 + 1180496 + 137559);
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );

        console.log("-----------------------------------");

        this.enableReward(0);
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );

        this.claimSpilloverReward(0, 0);
        console.log(
            "zero address rewards: ", _getZeroAddressRewards(stakingRewarded, reward, address(stakingDistributor))
        );
        console.log(
            "global accumulator: ", _getDistributionAccumulator(stakingRewarded, reward, address(stakingDistributor))
        );

        echidna_UPDATE_REWARDS_INVARIANT();
    }

    function test_UPDATE_REWARDS_INVARIANTS3() public {
        _delay(32737 + 279023 + 319648 + 53742);
        this.enableReward(0);
        _delay(177942 + 1239800);
        uint128[] memory rewards = new uint128[](1);
        rewards[0] = 10339251737;
        this.registerReward(1, 0, rewards);
        _delay(506572);
        this.enableReward(1);
        this.stake(1);
        echidna_UPDATE_REWARDS_INVARIANT();
        console.log("zero address rewards: ", stakingDistributor.totalRewardedEligible(stakingRewarded, reward));
        console.log("e2e rewarded: ", stakingRewarded);
        console.log("e2e reward: ", reward);
        this.claimSpilloverReward(0, 1);
        console.log("zero address rewards: ", stakingDistributor.totalRewardedEligible(stakingRewarded, reward));
        echidna_UPDATE_REWARDS_INVARIANT();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function getBytecode(address _contractAddress) internal view returns (bytes memory) {
        uint256 size;
        assembly {
            size := extcodesize(_contractAddress)
        }
        bytes memory bytecode = new bytes(size);
        assembly {
            extcodecopy(_contractAddress, add(bytecode, 0x20), 0, size)
        }
        return bytecode;
    }

    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }
}
