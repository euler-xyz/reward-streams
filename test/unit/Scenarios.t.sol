// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/StakingRewardStreamsHarness.sol";
import "../harness/StakingFreeRewardStreamsHarness.sol";
import "../utils/MockERC20.sol";
import "../utils/MockController.sol";

contract ScenarioTest is Test {
    EthereumVaultConnector internal evc;
    StakingRewardStreamsHarness internal stakingDistributor;
    StakingFreeRewardStreamsHarness internal stakingFreeDistributor;
    address internal stakingRewarded;
    address internal stakingFreeRewarded;
    address internal reward;
    address internal seeder;

    function setUp() external {
        evc = new EthereumVaultConnector();

        stakingDistributor = new StakingRewardStreamsHarness(evc, 10 days);
        stakingFreeDistributor = new StakingFreeRewardStreamsHarness(evc, 10 days);

        stakingRewarded = address(new MockERC20("Staking Rewarded", "SRWDD"));
        vm.label(stakingRewarded, "STAKING REWARDED");

        stakingFreeRewarded =
            address(new MockERC20BalanceForwarder(evc, stakingFreeDistributor, "Staking Free Rewarded", "SFRWDD"));
        vm.label(stakingFreeRewarded, "STAKING FREE REWARDED");

        reward = address(new MockERC20("Reward", "RWD"));
        vm.label(reward, "REWARD");

        seeder = vm.addr(0xabcdef);
        vm.label(seeder, "SEEDER");

        MockERC20(reward).mint(seeder, 100e18);

        vm.prank(seeder);
        MockERC20(reward).approve(address(stakingDistributor), type(uint256).max);

        vm.prank(seeder);
        MockERC20(reward).approve(address(stakingFreeDistributor), type(uint256).max);
    }

    // single rewarded and single reward; no participants so all the rewards should be earned by addresss(0)
    function test_Scenario_1(uint40 blockTimestamp, uint8 amountsLength, bytes memory seed) external {
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 25));

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // verify that address(0) hasn't earned anything yet
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that address(0) has earned rewards
        uint256 expectedAmount = 0;
        for (uint256 i; i <= amounts.length / 2; ++i) {
            if (i < amounts.length / 2) {
                expectedAmount += amounts[i];
            } else if (amounts.length % 2 == 1) {
                expectedAmount += amounts[i] / 2;
            }
        }
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), expectedAmount);
        assertEq(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), expectedAmount);

        // claim the rewards earned by address(0)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount);

        // verify total claimed
        assertEq(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), expectedAmount);
        assertEq(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), expectedAmount);

        // after claiming, rewards earned by address(0) should be zero
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0);

        // forward time to the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that address(0) has earned all the rest of the rewards
        expectedAmount = totalAmount - expectedAmount;
        assertApproxEqAbs(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), expectedAmount, 1
        );
        assertApproxEqAbs(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), expectedAmount, 1
        );

        // if updated with address(0) as a recipient, the rewards will not be claimed
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance);

        // claim the rewards earned by address(0)
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertApproxEqAbs(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, 1);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(this));
        assertApproxEqAbs(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, 1);

        // verify total claimed
        assertApproxEqAbs(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, 1);
        assertApproxEqAbs(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), totalAmount, 1);

        // after claiming, rewards earned by address(0) should be zero
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0);
    }

    // single rewarded and single reward; one participant who earns all the time
    function test_Scenario_2(
        uint40 blockTimestamp,
        uint8 amountsLength,
        bytes memory seed,
        address participant,
        uint128 balance
    ) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(stakingDistributor)
                && participant != stakingRewarded
        );
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 25));
        balance = uint128(bound(balance, 1, 100e18));

        uint256 ALLOWED_DELTA = 1e10; // 0.000001%

        // mint the rewarded tokens to the participant
        vm.startPrank(participant);
        vm.label(participant, "PARTICIPANT");
        MockERC20(stakingRewarded).mint(participant, balance);
        MockERC20(stakingFreeRewarded).mint(participant, balance);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // stake and enable rewards
        vm.startPrank(participant);
        stakingDistributor.stake(stakingRewarded, balance);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // verify that the participant hasn't earned anything yet
        assertEq(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(participant, stakingRewarded), balance);
        assertEq(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), balance);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that the participant has earned rewards
        uint256 expectedAmount = 0;
        for (uint256 i; i <= amounts.length / 2; ++i) {
            if (i < amounts.length / 2) {
                expectedAmount += amounts[i];
            } else if (amounts.length % 2 == 1) {
                expectedAmount += amounts[i] / 2;
            }
        }
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), expectedAmount, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );

        // update and claim the rewards earned by the participant (in two steps to check that both functions work)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingDistributor.updateReward(stakingRewarded, reward, participant);
        assertEq(MockERC20(reward).balanceOf(participant), preClaimBalance);

        stakingDistributor.claimReward(stakingRewarded, reward, participant, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, participant);
        assertEq(MockERC20(reward).balanceOf(participant), preClaimBalance);

        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), expectedAmount, ALLOWED_DELTA);
        assertApproxEqRel(
            stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), expectedAmount, ALLOWED_DELTA
        );

        // after claiming, rewards earned by the participant should be zero
        assertEq(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0);

        // forward time to the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that the participant has earned all the rest of the rewards
        expectedAmount = totalAmount - expectedAmount;
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), expectedAmount, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );

        // claim the rewards earned by the participant (will be transferred to this contract)
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.claimReward(stakingRewarded, reward, address(this), false);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, address(this), false);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, ALLOWED_DELTA);
        assertApproxEqRel(
            stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), totalAmount, ALLOWED_DELTA
        );

        // after claiming, rewards earned by the participant should be zero
        assertEq(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0);
        assertEq(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0);

        // SANITY CHECKS

        // disable rewards
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(participant, stakingRewarded), balance);
        assertEq(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 0);

        // enable rewards
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(participant, stakingRewarded), balance);
        assertEq(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), balance);

        // unstake and disable balance forwarding
        stakingDistributor.unstake(stakingRewarded, balance, participant, false);
        MockERC20BalanceForwarder(stakingFreeRewarded).disableBalanceForwarding();

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(participant, stakingRewarded), 0);
        assertEq(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 0);

        // disable rewards
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(participant, stakingRewarded), 0);
        assertEq(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 0);
    }

    // single rewarded and single reward; one participant who doesn't earn all the time
    function test_Scenario_3(
        uint40 blockTimestamp,
        uint8 amountsLength,
        bytes memory seed,
        address participant,
        uint128 balance
    ) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(stakingDistributor)
                && participant != stakingRewarded
        );
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 25));
        vm.assume(amountsLength % 4 == 0);
        balance = uint128(bound(balance, 2, 100e18));

        uint256 ALLOWED_DELTA = 1e10; // 0.000001%

        // mint the rewarded tokens to the participant
        vm.startPrank(participant);
        vm.label(participant, "PARTICIPANT");
        MockERC20(stakingRewarded).mint(participant, balance);
        MockERC20(stakingFreeRewarded).mint(participant, balance);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // stake and enable rewards
        vm.startPrank(participant);
        stakingDistributor.stake(stakingRewarded, balance);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // unstake/disable half of the balance
        stakingDistributor.unstake(stakingRewarded, balance / 2, participant, false);
        MockERC20(stakingFreeRewarded).transfer(address(evc), balance / 2);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // disable the rewards for some time (now address(0) should be earning them)
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // enable the rewards again
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // forward the time until the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // calculate how much address(0) should have earned (use the fact that amountsLength % 4 == 0)
        uint256 expectedAmount = 0;
        for (uint256 i = amounts.length / 2; i < 3 * amounts.length / 4; ++i) {
            expectedAmount += amounts[i];
        }

        // claim rewards for the participant and address(0)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingDistributor.claimReward(stakingRewarded, reward, participant, false);
        assertApproxEqRel(
            MockERC20(reward).balanceOf(participant), preClaimBalance + totalAmount - expectedAmount, ALLOWED_DELTA
        );

        preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant, false);
        assertApproxEqRel(
            MockERC20(reward).balanceOf(participant), preClaimBalance + totalAmount - expectedAmount, ALLOWED_DELTA
        );

        preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingDistributor.updateReward(stakingRewarded, reward, participant);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(participant);
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, participant);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, ALLOWED_DELTA);
        assertApproxEqRel(
            stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), totalAmount, ALLOWED_DELTA
        );

        // verify balances and total eligible
        assertApproxEqAbs(stakingDistributor.balanceOf(participant, stakingRewarded), balance / 2, 1);
        assertApproxEqAbs(stakingFreeDistributor.balanceOf(participant, stakingFreeRewarded), balance / 2, 1);
        assertApproxEqAbs(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance / 2, 1);
        assertApproxEqAbs(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), balance / 2, 1);
    }

    // single rewarded and single reward; multiple participants who don't earn all the time (hence address(0) earns some
    // rewards)
    function test_Scenario_4(uint40 blockTimestamp, address participant1, address participant2) external {
        vm.assume(
            participant1 != address(0) && participant1 != address(1) && participant1 != address(evc)
                && participant1 != address(stakingDistributor) && participant1 != stakingRewarded
        );
        vm.assume(
            participant2 != address(0) && participant2 != address(1) && participant2 != address(evc)
                && participant2 != address(stakingDistributor) && participant2 != stakingRewarded
        );
        vm.assume(participant1 != participant2);
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the staking free rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(stakingFreeRewarded).mint(address(1), 10e18);
        MockERC20(stakingFreeRewarded).approve(participant1, type(uint256).max);
        MockERC20(stakingFreeRewarded).approve(participant2, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(participant1);
        vm.label(participant1, "PARTICIPANT_1");
        MockERC20(stakingRewarded).mint(participant1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(participant2);
        vm.label(participant2, "PARTICIPANT_2");
        MockERC20(stakingRewarded).mint(participant2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        amounts[0] = 5e18;
        amounts[1] = 10e18;
        amounts[2] = 15e18;
        amounts[3] = 5e18;
        amounts[4] = 10e18;

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // participant 1 stakes and enables rewards, participant 2 doesn't do anything yet
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 1e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // participant1 enables the same reward again (nothing should change; coverage)
        vm.startPrank(participant1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 2 comes into play
        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 1e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 7.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 1 disables rewards
        vm.startPrank(participant1);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 1 enables rewards again and doubles down
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 1e18);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 8.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            8.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 6.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            6.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // both participants change their eligible balances
        vm.startPrank(participant1);
        stakingDistributor.unstake(stakingRewarded, 1e18, participant1, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 1e18);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 10.2083344e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            10.2083344e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 12.291667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            12.291667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 1 adds more balance; both participants have equal eligible balances now
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 7.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 16.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            16.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // both participants reduce their eligible balances to zero hence address(0) earns all the rewards in that
        // period
        vm.startPrank(participant1);
        stakingDistributor.unstake(stakingRewarded, 3e18, participant1, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 3e18);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.unstake(stakingRewarded, 3e18, participant2, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 3e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 16.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            16.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );

        // participant2 adds eligible balance again, address(0) no longer earns rewards
        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 5e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 5e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 17.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            17.916667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );

        // participant1 joins participant2 and adds the same eligible balance as participant2
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 5e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 5e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // participant1 updates the reward data for himself, claiming the address(0) rewards
        vm.startPrank(participant1);
        uint256 preBalance = MockERC20(reward).balanceOf(participant1);
        stakingDistributor.updateReward(stakingRewarded, reward, participant1);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preBalance + 1.25e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(participant1);
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, participant1);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preBalance + 1.25e18, ALLOWED_DELTA);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // participant2 updates the reward data for himself too, but there's nothing to claim for address(0)
        vm.startPrank(participant2);
        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingDistributor.updateReward(stakingRewarded, reward, participant2);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance, 0);

        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, participant2);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance, 0);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 16.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            16.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant2 reduces his eligible balance to zero
        vm.startPrank(participant2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        MockERC20BalanceForwarder(stakingFreeRewarded).disableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 21.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            21.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant1 opts out too; now address(0) earns all the rewards
        vm.startPrank(participant1);
        stakingDistributor.unstake(stakingRewarded, 5e18, participant1, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 21.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            21.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );

        // participant1 claims their rewards
        vm.startPrank(participant1);
        preBalance = MockERC20(reward).balanceOf(participant1);
        stakingDistributor.claimReward(stakingRewarded, reward, participant1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preBalance + 21.458334e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(participant1);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preBalance + 21.458334e18, ALLOWED_DELTA);
        vm.stopPrank();

        // participant2 claims their rewards
        vm.startPrank(participant2);
        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingDistributor.claimReward(stakingRewarded, reward, participant2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance + 19.791667e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance + 19.791667e18, ALLOWED_DELTA);
        vm.stopPrank();

        // participant2 also claims the address(0) rewards
        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingDistributor.updateReward(stakingRewarded, reward, participant2);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance + 2.5e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(participant2);
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, participant2);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preBalance + 2.5e18, ALLOWED_DELTA);

        // sanity checks
        vm.warp(block.timestamp + 50 days);
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);
        assertEq(stakingDistributor.enabledRewards(participant1, stakingRewarded)[0], reward);
        assertEq(stakingDistributor.enabledRewards(participant2, stakingRewarded).length, 0);
        assertEq(stakingFreeDistributor.enabledRewards(participant1, stakingFreeRewarded).length, 0);
        assertEq(stakingFreeDistributor.enabledRewards(participant2, stakingFreeRewarded)[0], reward);
        assertEq(stakingDistributor.balanceOf(participant1, stakingRewarded), 0);
        assertEq(stakingDistributor.balanceOf(participant2, stakingRewarded), 5e18);
        assertEq(stakingFreeDistributor.balanceOf(participant1, stakingFreeRewarded), 5e18);
        assertEq(stakingFreeDistributor.balanceOf(participant2, stakingFreeRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 0);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 45e18);
        assertEq(stakingFreeDistributor.totalRewardRegistered(stakingFreeRewarded, reward), 45e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 45e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), 45e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), 2 * 21.458334e18 + 2 * 1.25e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), 2 * 19.791667e18 + 2 * 2.5e18, ALLOWED_DELTA);
    }

    // single rewarded and multiple rewards; multiple participants who don't earn all the time (hence address(0) earns
    // some rewards)
    function test_Scenario_5(uint40 blockTimestamp, address participant1, address participant2) external {
        vm.assume(
            participant1 != address(0) && participant1 != address(1) && participant1 != address(evc)
                && participant1 != address(stakingDistributor) && participant1 != stakingRewarded
        );
        vm.assume(
            participant2 != address(0) && participant2 != address(1) && participant2 != address(evc)
                && participant2 != address(stakingDistributor) && participant2 != stakingRewarded
        );
        vm.assume(participant1 != participant2);
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // deploy another reward token, mint it to the seeder and approve both distributors
        vm.startPrank(seeder);
        address reward2 = address(new MockERC20("Reward2", "RWD2"));
        vm.label(reward2, "REWARD2");
        MockERC20(reward2).mint(seeder, 100e18);
        MockERC20(reward2).approve(address(stakingDistributor), type(uint256).max);
        MockERC20(reward2).approve(address(stakingFreeDistributor), type(uint256).max);
        vm.stopPrank();

        // mint the staking free rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(stakingFreeRewarded).mint(address(1), 10e18);
        MockERC20(stakingFreeRewarded).approve(participant1, type(uint256).max);
        MockERC20(stakingFreeRewarded).approve(participant2, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(participant1);
        vm.label(participant1, "PARTICIPANT_1");
        MockERC20(stakingRewarded).mint(participant1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(participant2);
        vm.label(participant2, "PARTICIPANT_2");
        MockERC20(stakingRewarded).mint(participant2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts1 = new uint128[](5);
        amounts1[0] = 2e18;
        amounts1[1] = 2e18;
        amounts1[2] = 0;
        amounts1[3] = 5e18;
        amounts1[4] = 10e18;

        uint128[] memory amounts2 = new uint128[](5);
        amounts2[0] = 0;
        amounts2[1] = 4e18;
        amounts2[2] = 1e18;
        amounts2[3] = 4e18;
        amounts2[4] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts1);
        stakingDistributor.registerReward(stakingRewarded, reward2, 0, amounts2);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts1);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward2, 0, amounts2);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // participant 1: enables both rewards
        // participant 2: enables only reward2
        vm.startPrank(participant1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.enableReward(stakingRewarded, reward2);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.enableReward(stakingRewarded, reward2);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        vm.stopPrank();

        // forward the time (address (0) earns rewards because none of the participants have eligible balances)
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // participant 1: has eligible balance for both rewards
        // participant 2: has eligible balance only for reward2
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 1e18);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            0.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // participant 1: increases eligible balance for both rewards
        // participant 2: increases eligible balance for both rewards
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 1e18);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 2e18);

        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            2.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            0.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 2.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            2.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // participant 1: disables reward2
        // participant 2: disables reward
        vm.startPrank(participant1);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward2, false);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            2.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            0.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 3.166667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            3.166667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // participant 1: enables reward2 again, but disables reward
        // participant 2: does nothing
        vm.startPrank(participant1);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            2.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            0.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            1.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);

        // participant 1: gets rid of the eligible balance
        // participant 2: disables reward2, but enables reward
        vm.startPrank(participant1);
        stakingDistributor.unstake(stakingRewarded, 2e18, participant1, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 2e18);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward2, false);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            2.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 3.166667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            3.166667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            1.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: increases eligible balance and enables both rewards
        // participant 2: does nothing
        vm.startPrank(participant1);
        stakingDistributor.stake(stakingRewarded, 4e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 4e18);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 3.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            3.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 4.416667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            4.416667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: disables reward2
        // participant 2: enables reward2
        vm.startPrank(participant1);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward2, false);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            6.083334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            6.916667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            8.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: enables reward2 again, but reduces eligible balance
        // participant 2: disables reward and gets rid of the eligible balance
        vm.startPrank(participant1);
        stakingDistributor.unstake(stakingRewarded, 2e18, participant1, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 2e18);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward2);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        stakingDistributor.unstake(stakingRewarded, 4e18, participant2, false);
        MockERC20(stakingFreeRewarded).transfer(address(1), 4e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 11.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            11.083334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            6.916667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            8.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            8.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: disables both rewards and forfeits the most recent rewards (they should accrue to address(0)
        // because participant2 has no eligible balance)
        // participant 2: increases eligible balance (it doesn't matter though because all the rewards are still earned
        // by address(0) - participant2 has had no eligible balance)
        vm.startPrank(participant1);
        stakingDistributor.disableReward(stakingRewarded, reward, true);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, true);
        stakingDistributor.disableReward(stakingRewarded, reward2, true);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward2, true);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 1e18);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            6.083334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            6.916667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false),
            3.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false),
            8.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 7e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 7e18, ALLOWED_DELTA
        );

        // participant1 claims rewards
        vm.startPrank(participant1);
        uint256 preRewardBalance = MockERC20(reward).balanceOf(participant1);
        stakingDistributor.claimReward(stakingRewarded, reward, participant1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preRewardBalance + 6.083334e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(participant1);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preRewardBalance + 6.083334e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(participant1);
        stakingDistributor.claimReward(stakingRewarded, reward2, participant1, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant1), preRewardBalance + 3.5e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(participant1);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward2, participant1, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant1), preRewardBalance + 3.5e18, ALLOWED_DELTA);
        vm.stopPrank();

        // participant2 claims rewards
        vm.startPrank(participant2);
        preRewardBalance = MockERC20(reward).balanceOf(participant2);
        stakingDistributor.claimReward(stakingRewarded, reward, participant2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preRewardBalance + 6.916667e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(participant2);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preRewardBalance + 6.916667e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(participant2);
        stakingDistributor.claimReward(stakingRewarded, reward2, participant2, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant2), preRewardBalance + 8.5e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(participant2);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward2, participant2, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant2), preRewardBalance + 8.5e18, ALLOWED_DELTA);
        vm.stopPrank();

        // this contract claims whatever was earned by address(0)
        preRewardBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preRewardBalance + 6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(address(this));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(this));
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preRewardBalance + 6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward2, address(this));
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), preRewardBalance + 7e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(address(this));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward2, address(this));
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), preRewardBalance + 7e18, ALLOWED_DELTA);

        // sanity checks
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant1, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(participant2, stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward2, false), 0, 0);
        assertEq(stakingDistributor.enabledRewards(participant1, stakingRewarded).length, 0);
        assertEq(stakingFreeDistributor.enabledRewards(participant1, stakingFreeRewarded).length, 0);
        assertEq(stakingDistributor.enabledRewards(participant2, stakingRewarded)[0], reward2);
        assertEq(stakingFreeDistributor.enabledRewards(participant2, stakingFreeRewarded)[0], reward2);
        assertEq(stakingDistributor.balanceOf(participant1, stakingRewarded), 2e18);
        assertEq(stakingDistributor.balanceOf(participant2, stakingRewarded), 1e18);
        assertEq(stakingFreeDistributor.balanceOf(participant1, stakingFreeRewarded), 2e18);
        assertEq(stakingFreeDistributor.balanceOf(participant2, stakingFreeRewarded), 1e18);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward2), 1e18);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward2), 1e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 19e18);
        assertEq(stakingFreeDistributor.totalRewardRegistered(stakingFreeRewarded, reward), 19e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward2), 19e18);
        assertEq(stakingFreeDistributor.totalRewardRegistered(stakingFreeRewarded, reward2), 19e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward2), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward2), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), 2 * 6.083334e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant1), 2 * 3.5e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), 2 * 6.916667e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(participant2), 2 * 8.5e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), 2 * 6e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), 2 * 7e18, ALLOWED_DELTA);
    }

    // single rewarded and single reward; multiple participants who don't earn all the time (hence address(0) earns
    // some rewards)
    function test_Scenario_6(
        uint40 blockTimestamp,
        address participant1,
        address participant2,
        address participant3
    ) external {
        vm.assume(
            participant1 != address(0) && participant1 != address(1) && participant1 != address(evc)
                && participant1 != address(stakingDistributor) && participant1 != stakingRewarded
        );
        vm.assume(
            participant2 != address(0) && participant2 != address(1) && participant2 != address(evc)
                && participant2 != address(stakingDistributor) && participant2 != stakingRewarded
        );
        vm.assume(
            participant3 != address(0) && participant3 != address(1) && participant3 != address(evc)
                && participant3 != address(stakingDistributor) && participant3 != stakingRewarded
        );
        vm.assume(participant1 != participant2 && participant1 != participant3 && participant2 != participant3);
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the staking free rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(stakingFreeRewarded).mint(address(1), 10e18);
        MockERC20(stakingFreeRewarded).approve(participant1, type(uint256).max);
        MockERC20(stakingFreeRewarded).approve(participant2, type(uint256).max);
        MockERC20(stakingFreeRewarded).approve(participant3, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(participant1);
        vm.label(participant1, "PARTICIPANT_1");
        MockERC20(stakingRewarded).mint(participant1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(participant2);
        vm.label(participant2, "PARTICIPANT_2");
        MockERC20(stakingRewarded).mint(participant2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(participant3);
        vm.label(participant3, "PARTICIPANT_3");
        MockERC20(stakingRewarded).mint(participant3, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 3 epochs
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 5e18;
        amounts[1] = 10e18;
        amounts[2] = 20e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme + 1 day
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 1 days);

        // participant 1: enables reward and increases eligible balance
        // participant 2: enables reward and increases eligible balance
        // participant 3: does nothing
        vm.startPrank(participant1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.stake(stakingRewarded, 1e18);

        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant1, 1e18);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.stake(stakingRewarded, 4e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant2, 4e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 14 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 1.9e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 1.9e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 7.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 7.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingDistributor.earnedReward(participant3, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // participant 3: enables reward and increases eligible balance
        vm.startPrank(participant3);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.stake(stakingRewarded, 5e18);

        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        MockERC20(stakingFreeRewarded).transferFrom(address(1), participant3, 5e18);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 2.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 2.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 9.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 9.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // checkpoint the rewards, each participate updates the data for themselves
        vm.startPrank(participant1);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(participant3);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // participant 3: disables and forfeits the reward
        vm.startPrank(participant3);
        stakingDistributor.unstake(stakingRewarded, 5e18, participant3, true);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, true);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 4.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 4.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 17.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false),
            17.6e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // checkpoint the rewards, each participate updates the data for themselves
        vm.startPrank(participant1);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(participant2);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(participant3);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        stakingFreeDistributor.updateReward(stakingFreeRewarded, reward, address(0));
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 25 days);

        // participant 1: claims their rewards forgiving the most recent ones
        vm.startPrank(participant1);
        uint256 preRewardBalance = MockERC20(reward).balanceOf(participant1);
        stakingDistributor.claimReward(stakingRewarded, reward, participant1, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preRewardBalance + 4.4e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(participant1);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant1, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), preRewardBalance + 4.4e18, ALLOWED_DELTA);
        vm.stopPrank();

        // participant 2: claims their rewards forgiving the most recent ones and gets rid of the eligible balance
        vm.startPrank(participant2);
        preRewardBalance = MockERC20(reward).balanceOf(participant2);
        stakingDistributor.claimReward(stakingRewarded, reward, participant2, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preRewardBalance + 17.6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(participant2);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant2, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), preRewardBalance + 17.6e18, ALLOWED_DELTA);

        stakingDistributor.unstake(stakingRewarded, 4e18, participant2, true);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, true);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant1, stakingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant2, stakingRewarded, reward, false), 0, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // sanity checks
        assertEq(stakingDistributor.enabledRewards(participant1, stakingRewarded)[0], reward);
        assertEq(stakingFreeDistributor.enabledRewards(participant1, stakingFreeRewarded)[0], reward);
        assertEq(stakingDistributor.enabledRewards(participant2, stakingRewarded)[0], reward);
        assertEq(stakingFreeDistributor.enabledRewards(participant2, stakingFreeRewarded).length, 0);
        assertEq(stakingDistributor.enabledRewards(participant3, stakingRewarded)[0], reward);
        assertEq(stakingFreeDistributor.enabledRewards(participant3, stakingFreeRewarded).length, 0);
        assertEq(stakingDistributor.balanceOf(participant1, stakingRewarded), 1e18);
        assertEq(stakingDistributor.balanceOf(participant2, stakingRewarded), 0);
        assertEq(stakingDistributor.balanceOf(participant3, stakingRewarded), 0);
        assertEq(stakingFreeDistributor.balanceOf(participant1, stakingFreeRewarded), 1e18);
        assertEq(stakingFreeDistributor.balanceOf(participant2, stakingFreeRewarded), 4e18);
        assertEq(stakingFreeDistributor.balanceOf(participant3, stakingFreeRewarded), 5e18);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 1e18);
        assertEq(stakingFreeDistributor.totalRewardedEligible(stakingFreeRewarded, reward), 1e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 35e18);
        assertEq(stakingFreeDistributor.totalRewardRegistered(stakingFreeRewarded, reward), 35e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 22e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingFreeDistributor.totalRewardClaimed(stakingFreeRewarded, reward), 22e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant1), 2 * 4.4e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant2), 2 * 17.6e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(participant3), 0, 0);
    }

    // balance tracker hook test
    function test_Scenario_7(
        uint40 blockTimestamp,
        address participant1,
        address participant2,
        address participant3
    ) external {
        vm.assume(participant1 != address(0) && participant1 != address(evc));
        vm.assume(participant2 != address(0) && participant2 != address(evc));
        vm.assume(participant3 != address(0) && participant3 != address(evc));
        vm.assume(participant1 != participant2 && participant1 != participant3 && participant2 != participant3);
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the staking free rewarded token to participant 1
        MockERC20(stakingFreeRewarded).mint(participant1, 10e18);

        vm.label(participant1, "PARTICIPANT_1");
        vm.label(participant2, "PARTICIPANT_2");
        vm.label(participant3, "PARTICIPANT_3");

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        amounts[0] = 10e18;
        amounts[1] = 10e18;
        amounts[2] = 10e18;
        amounts[3] = 10e18;
        amounts[4] = 10e18;

        // register the distribution scheme
        vm.startPrank(seeder);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // all participants enable reward and balance forwarding but only participant 1 has eligible balance at this
        // point
        vm.startPrank(participant1);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        vm.startPrank(participant2);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        vm.startPrank(participant3);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time to the middle of the second epoch of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 15 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false), 15e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 1 transfers tokens to participant 2
        vm.prank(participant1);
        MockERC20(stakingFreeRewarded).transfer(participant2, 5e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            17.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 2 transfers tokens to participant 3
        vm.prank(participant2);
        MockERC20(stakingFreeRewarded).transfer(participant3, 5e18);

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            22.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 3 gets all the tokens
        vm.prank(participant1);
        MockERC20(stakingFreeRewarded).transfer(participant3, 5e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            22.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 3 transfers all tokens to participant 2
        vm.prank(participant3);
        MockERC20(stakingFreeRewarded).transfer(participant2, 10e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            22.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 0, 0);

        // participant 2 transfers all tokens to an address that doesn't have the balance tracker enabled (i.e.
        // stakingFreeRewarded contract)
        vm.prank(participant2);
        MockERC20(stakingFreeRewarded).transfer(stakingFreeRewarded, 10e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            22.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );

        // stakingFreeRewarded transfers the tokens to participant 1 and participant 3
        vm.prank(stakingFreeRewarded);
        MockERC20(stakingFreeRewarded).transfer(participant1, 2e18);

        vm.prank(stakingFreeRewarded);
        MockERC20(stakingFreeRewarded).transfer(participant3, 8e18);

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant1, stakingFreeRewarded, reward, false),
            23.5e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant2, stakingFreeRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant3, stakingFreeRewarded, reward, false), 14e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
    }

    // staking/unstaking within the same block
    function test_Scenario_8(uint40 blockTimestamp, address participant) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(stakingDistributor)
                && participant != stakingRewarded
        );
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        // mint the staking free rewarded token to the participant
        MockERC20(stakingRewarded).mint(participant, 10e18);
        MockERC20(stakingFreeRewarded).mint(participant, 10e18);

        vm.prank(participant);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.label(participant, "PARTICIPANT");

        vm.warp(blockTimestamp);

        // prepare the amounts; 1 epoch
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the middle of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 5 days);

        // enable reward and balance forwarding
        vm.startPrank(participant);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 10);

        // verify earnings
        assertApproxEqRel(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0, 0);

        // verify that staking (or enabling balance forwarding) and unstaking (or disabling balance forwarding) within
        // the same block does not earn any rewards
        vm.startPrank(participant);
        stakingDistributor.stake(stakingRewarded, 10e18);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();

        assertApproxEqRel(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0, 0);

        stakingDistributor.unstake(stakingRewarded, 10e18, participant, true);
        MockERC20BalanceForwarder(stakingFreeRewarded).disableBalanceForwarding();

        assertApproxEqRel(stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), 0, 0);
        assertApproxEqRel(stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), 0, 0);

        // try to claim
        uint256 preBalance = MockERC20(reward).balanceOf(participant);
        stakingDistributor.claimReward(stakingRewarded, reward, participant, false);
        stakingFreeDistributor.claimReward(stakingFreeRewarded, reward, participant, false);
        assertEq(MockERC20(reward).balanceOf(participant), preBalance);
        vm.stopPrank();
    }

    // reward and rewarded are the same
    function test_Scenario_9(uint40 blockTimestamp, address participant) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(stakingDistributor)
                && participant != stakingRewarded
        );
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        // mint the tokens
        MockERC20(stakingRewarded).mint(seeder, 100e18);
        MockERC20(stakingRewarded).mint(participant, 100e18);
        MockERC20(stakingFreeRewarded).mint(seeder, 100e18);
        MockERC20(stakingFreeRewarded).mint(participant, 100e18);

        vm.prank(seeder);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.prank(seeder);
        MockERC20(stakingFreeRewarded).approve(address(stakingFreeDistributor), type(uint256).max);

        vm.prank(participant);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.label(participant, "PARTICIPANT");

        vm.warp(blockTimestamp);

        // prepare the amounts; 1 epoch
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, stakingRewarded, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, stakingFreeRewarded, 0, amounts);
        vm.stopPrank();

        // forward the time to the beginning of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // enable reward and balance forwarding, stake
        vm.startPrank(participant);
        stakingDistributor.enableReward(stakingRewarded, stakingRewarded);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, stakingFreeRewarded);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant, stakingRewarded, stakingRewarded, false), 10e18, 0
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, stakingFreeRewarded, false), 10e18, 0
        );

        // claim and unstake
        vm.startPrank(participant);
        uint256 preBalance = MockERC20(stakingRewarded).balanceOf(participant);
        stakingDistributor.claimReward(stakingRewarded, stakingRewarded, participant, false);
        stakingDistributor.unstake(stakingRewarded, 1e18, participant, true);
        assertEq(MockERC20(stakingRewarded).balanceOf(participant), preBalance + 11e18);

        preBalance = MockERC20(stakingFreeRewarded).balanceOf(participant);
        stakingDistributor.claimReward(stakingFreeRewarded, stakingFreeRewarded, participant, false);
        assertEq(MockERC20(stakingRewarded).balanceOf(participant), preBalance + 10e18);
    }

    function test_Scenario_Liquidation(uint40 blockTimestamp, address participant) external {
        vm.assume(participant != address(0) && participant != address(evc));
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        address[] memory rewards = new address[](5);
        for (uint256 i = 0; i < rewards.length; i++) {
            rewards[i] = address(new MockERC20("Reward", "RWD"));

            MockERC20(rewards[i]).mint(seeder, 100e18);

            vm.prank(seeder);
            MockERC20(rewards[i]).approve(address(stakingFreeDistributor), type(uint256).max);
        }

        // mint the tokens
        MockERC20(stakingFreeRewarded).mint(participant, 100e18);
        vm.label(participant, "PARTICIPANT");

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = 1e18;
        }

        // register the distribution scheme
        vm.startPrank(seeder);
        for (uint256 i = 0; i < rewards.length; i++) {
            stakingFreeDistributor.registerReward(stakingFreeRewarded, rewards[i], 0, amounts);
        }
        vm.stopPrank();

        // forward the time to the beginning of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // enable reward and balance forwarding, stake
        vm.startPrank(participant);
        for (uint256 i = 0; i < rewards.length; i++) {
            stakingFreeDistributor.enableReward(stakingFreeRewarded, rewards[i]);
        }
        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();

        // for coverage
        vm.expectRevert(BaseRewardStreams.TooManyRewardsEnabled.selector);
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // deploy mock controller
        address controller = address(new MockController(evc));

        // enable collateral
        evc.enableCollateral(participant, stakingFreeRewarded);

        // enable controller
        evc.enableController(participant, controller);

        // forward the time
        vm.warp(block.timestamp + 50 days);

        // controller liquidates
        uint256 preBalance = MockERC20(stakingFreeRewarded).balanceOf(participant);
        MockController(controller).liquidateCollateralShares(
            stakingFreeRewarded, participant, stakingFreeRewarded, 10e18
        );
        assertEq(MockERC20(stakingFreeRewarded).balanceOf(participant), preBalance - 10e18);
    }

    function test_Scenario_Overflow(uint256 blockTimestamp, address participant) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(stakingDistributor)
                && participant != stakingRewarded
        );
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 365 days));

        // mint more reward tokens to the seeder
        MockERC20(reward).mint(seeder, type(uint256).max - MockERC20(reward).balanceOf(seeder));

        // mint the staking free rewarded token to the participant
        MockERC20(stakingFreeRewarded).mint(participant, 10e18);

        // mint the tokens to the participant
        vm.startPrank(participant);
        MockERC20(stakingRewarded).mint(participant, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 3 epochs
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = type(uint96).max / 2 + 1;
        amounts[1] = type(uint96).max / 2 + 1;
        amounts[2] = type(uint96).max / 2 + 1;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        stakingFreeDistributor.registerReward(stakingFreeRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // enable rewards and stake
        vm.startPrank(participant);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.stake(stakingRewarded, 1e18);

        MockERC20BalanceForwarder(stakingFreeRewarded).enableBalanceForwarding();
        stakingFreeDistributor.enableReward(stakingFreeRewarded, reward);

        // forward the time to the end of the distribution scheme
        vm.warp(block.timestamp + 30 days);

        // disable rewards. when updating, the amount earned will overflow and the excess amount will be credited to
        // address(0)
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        stakingFreeDistributor.disableReward(stakingFreeRewarded, reward, false);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(participant, stakingRewarded, reward, false), type(uint96).max, 0
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(participant, stakingFreeRewarded, reward, false), type(uint96).max, 0
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false),
            stakingDistributor.totalRewardRegistered(stakingRewarded, reward) - type(uint96).max,
            0
        );
        assertApproxEqRel(
            stakingFreeDistributor.earnedReward(address(0), stakingFreeRewarded, reward, false),
            stakingFreeDistributor.totalRewardRegistered(stakingFreeRewarded, reward) - type(uint96).max,
            0
        );
    }
}
