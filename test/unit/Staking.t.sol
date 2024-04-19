// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/StakingRewardStreamsHarness.sol";
import {MockERC20, MockERC20Malicious} from "../utils/MockERC20.sol";
import {MockController} from "../utils/MockController.sol";

contract StakingTest is Test {
    EthereumVaultConnector internal evc;
    StakingRewardStreamsHarness internal distributor;
    address internal rewarded;
    address internal rewardedMalicious;

    function setUp() external {
        evc = new EthereumVaultConnector();
        distributor = new StakingRewardStreamsHarness(address(evc), 10 days);
        rewarded = address(new MockERC20("Rewarded", "RWDD"));
        rewardedMalicious = address(new MockERC20Malicious("RewardedMalicious", "RWDMLC"));
    }

    function test_StakeAndUnstake(address participant, uint64 amount, address recipient) external {
        vm.assume(
            participant != address(0) && participant != address(evc) && participant != address(distributor)
                && participant != rewarded
        );
        vm.assume(
            recipient != address(0) && recipient != address(evc) && recipient != address(distributor)
                && recipient != rewarded
        );
        vm.assume(amount > 0);

        // mint tokens and approve
        vm.startPrank(participant);
        MockERC20(rewarded).mint(participant, 10 * uint256(amount));
        MockERC20(rewarded).approve(address(distributor), type(uint256).max);
        MockERC20(rewardedMalicious).mint(participant, 10 * uint256(amount));
        MockERC20(rewardedMalicious).approve(address(distributor), type(uint256).max);

        // stake 0 amount
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.stake(rewarded, 0);

        // stake
        uint256 preBalanceParticipant = MockERC20(rewarded).balanceOf(participant);
        uint256 preBalanceDistributor = MockERC20(rewarded).balanceOf(address(distributor));
        distributor.stake(rewarded, amount);
        assertEq(MockERC20(rewarded).balanceOf(participant), preBalanceParticipant - amount);
        assertEq(MockERC20(rewarded).balanceOf(address(distributor)), preBalanceDistributor + amount);

        // unstake 0 amount
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.unstake(rewarded, 0, participant, false);

        // unstake greater than staked amount
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.unstake(rewarded, uint256(amount) + 1, participant, false);

        // unstake
        uint256 preBalanceRecipient = MockERC20(rewarded).balanceOf(recipient);
        preBalanceDistributor = MockERC20(rewarded).balanceOf(address(distributor));
        distributor.unstake(rewarded, amount, recipient, false);
        assertEq(MockERC20(rewarded).balanceOf(recipient), preBalanceRecipient + amount);
        assertEq(MockERC20(rewarded).balanceOf(address(distributor)), preBalanceDistributor - amount);

        // stake max
        preBalanceParticipant = MockERC20(rewarded).balanceOf(participant);
        preBalanceDistributor = MockERC20(rewarded).balanceOf(address(distributor));
        distributor.stake(rewarded, type(uint256).max);
        assertEq(MockERC20(rewarded).balanceOf(participant), 0);
        assertEq(MockERC20(rewarded).balanceOf(address(distributor)), preBalanceDistributor + preBalanceParticipant);

        // unstake max
        preBalanceRecipient = MockERC20(rewarded).balanceOf(recipient);
        preBalanceDistributor = MockERC20(rewarded).balanceOf(address(distributor));
        distributor.unstake(rewarded, type(uint256).max, recipient, false);
        assertEq(MockERC20(rewarded).balanceOf(recipient), preBalanceRecipient + preBalanceDistributor);
        assertEq(MockERC20(rewarded).balanceOf(address(distributor)), 0);

        // stake malicious
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.stake(rewardedMalicious, amount);

        vm.stopPrank();
    }
}
