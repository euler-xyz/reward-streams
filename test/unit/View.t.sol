// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/BaseRewardStreamsHarness.sol";
import "../utils/MockERC20.sol";
import "../utils/MockController.sol";

contract ViewTest is Test {
    EthereumVaultConnector internal evc;
    BaseRewardStreamsHarness internal distributor;

    function setUp() external {
        evc = new EthereumVaultConnector();
        distributor = new BaseRewardStreamsHarness(evc, 10 days);
    }

    function test_EnabledRewards(address account, address rewarded, uint8 n, bytes memory seed) external {
        n = uint8(bound(n, 1, 5));

        vm.startPrank(account);
        for (uint8 i = 0; i < n; i++) {
            address reward = address(uint160(uint256(keccak256(abi.encode(seed, i)))));
            distributor.enableReward(rewarded, reward);

            address[] memory enabledRewards = distributor.enabledRewards(account, rewarded);
            assertEq(enabledRewards.length, i + 1);
            assertEq(enabledRewards[i], reward);
        }
    }

    function test_BalanceOf(address account, address rewarded, uint256 balance) external {
        distributor.setAccountBalance(account, rewarded, balance);
        assertEq(distributor.balanceOf(account, rewarded), balance);
    }

    function test_RewardAmountCurrent(
        address rewarded,
        address reward,
        uint40 blockTimestamp,
        uint128 amount
    ) external {
        uint40 epoch = distributor.getEpoch(blockTimestamp);
        distributor.setDistributionAmount(rewarded, reward, epoch, amount);
        vm.warp(blockTimestamp);
        assertEq(distributor.rewardAmount(rewarded, reward), amount);
    }

    function test_RewardAmount(address rewarded, address reward, uint40 epoch, uint128 amount) external {
        distributor.setDistributionAmount(rewarded, reward, epoch, amount);
        assertEq(distributor.rewardAmount(rewarded, reward, epoch), amount);
    }

    function test_totalRewardedEligible(address rewarded, address reward, uint256 total) external {
        BaseRewardStreams.TotalsStorage memory totals;
        totals.totalEligible = total;

        distributor.setDistributionTotals(rewarded, reward, totals);
        assertEq(distributor.totalRewardedEligible(rewarded, reward), totals.totalEligible);
    }

    function test_totalRewardRegistered(address rewarded, address reward, uint128 total) external {
        BaseRewardStreams.TotalsStorage memory totals;
        totals.totalRegistered = total;

        distributor.setDistributionTotals(rewarded, reward, totals);
        assertEq(distributor.totalRewardRegistered(rewarded, reward), totals.totalRegistered);
    }

    function test_totalRewardClaimed(address rewarded, address reward, uint128 total) external {
        BaseRewardStreams.TotalsStorage memory totals;
        totals.totalClaimed = total;

        distributor.setDistributionTotals(rewarded, reward, totals);
        assertEq(distributor.totalRewardClaimed(rewarded, reward), totals.totalClaimed);
    }

    function test_Epoch(uint40 timestamp) external {
        vm.assume(timestamp < type(uint40).max - distributor.EPOCH_DURATION());
        vm.warp(timestamp);

        assertEq(distributor.getEpoch(timestamp), distributor.currentEpoch());
        assertEq(distributor.currentEpoch(), timestamp / distributor.EPOCH_DURATION());
        assertEq(
            distributor.getEpochStartTimestamp(distributor.currentEpoch()),
            distributor.currentEpoch() * distributor.EPOCH_DURATION()
        );
        assertEq(
            distributor.getEpochEndTimestamp(distributor.currentEpoch()),
            distributor.getEpochStartTimestamp(distributor.currentEpoch()) + distributor.EPOCH_DURATION()
        );
    }

    function test_msgSender(address caller) external {
        vm.assume(caller != address(0) && caller != address(evc));

        vm.startPrank(caller);
        assertEq(distributor.msgSender(), caller);

        vm.startPrank(caller);
        bytes memory result =
            evc.call(address(distributor), caller, 0, abi.encodeWithSelector(distributor.msgSender.selector));
        assertEq(abi.decode(result, (address)), caller);
    }
}
