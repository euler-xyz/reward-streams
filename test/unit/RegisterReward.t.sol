// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/BaseRewardStreamsHarness.sol";
import "../utils/MockERC20.sol";

contract RegisterRewardTest is Test {
    EthereumVaultConnector internal evc;
    BaseRewardStreamsHarness internal distributor;
    mapping(address rewarded => mapping(address reward => mapping(uint256 epoch => uint256 amount))) internal
        distributionAmounts;
    address internal rewarded;
    address internal reward;
    address internal seeder;

    function setUp() external {
        evc = new EthereumVaultConnector();

        distributor = new BaseRewardStreamsHarness(evc, 10 days);

        rewarded = address(new MockERC20("Rewarded", "RWDD"));
        vm.label(rewarded, "REWARDED");

        reward = address(new MockERC20("Reward", "RWD"));
        vm.label(reward, "REWARD");

        seeder = vm.addr(0xabcdef);
        vm.label(seeder, "SEEDER");

        MockERC20(reward).mint(seeder, 100e18);

        vm.prank(seeder);
        MockERC20(reward).approve(address(distributor), type(uint256).max);
    }

    function updateDistributionAmounts(
        address _rewarded,
        address _reward,
        uint40 _startEpoch,
        uint128[] memory _amounts
    ) internal {
        for (uint256 i; i < _amounts.length; ++i) {
            distributionAmounts[_rewarded][_reward][_startEpoch + i] += _amounts[i];
        }
    }

    function test_RevertIfInvalidEpochDuration_Constructor(uint40 epochDuration) external {
        if (epochDuration < 7 days) {
            vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        }

        new BaseRewardStreamsHarness(IEVC(address(0)), epochDuration);
    }

    function test_RegisterReward(
        uint40 epochDuration,
        uint40 blockTimestamp,
        uint40 startEpoch,
        uint8 amountsLength0,
        uint8 amountsLength1,
        uint8 amountsLength2,
        bytes memory seed
    ) external {
        epochDuration = uint40(bound(epochDuration, 7 days, 365 days));
        blockTimestamp = uint40(bound(blockTimestamp, 1, type(uint40).max - 50 * epochDuration));
        amountsLength0 = uint8(bound(amountsLength0, 1, 25));
        amountsLength1 = uint8(bound(amountsLength1, 1, 25));
        amountsLength2 = uint8(bound(amountsLength2, 1, 25));

        vm.warp(blockTimestamp);
        distributor = new BaseRewardStreamsHarness(evc, epochDuration);

        vm.startPrank(seeder);
        MockERC20(reward).approve(address(distributor), type(uint256).max);

        // ------------------ 1st call ------------------
        // prepare the start epoch
        startEpoch = uint40(
            bound(
                startEpoch, distributor.currentEpoch() + 1, distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD()
            )
        );

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength0);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, startEpoch, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), totalAmount);

        // verify that the distribution and totals storage were properly initialized
        assertEq(
            abi.encode(distributor.getDistribution(rewarded, reward)),
            abi.encode(BaseRewardStreams.DistributionStorage({lastUpdated: uint40(block.timestamp), accumulator: 0}))
        );
        assertEq(
            abi.encode(distributor.getTotals(rewarded, reward)),
            abi.encode(
                BaseRewardStreams.TotalsStorage({totalRegistered: totalAmount, totalClaimed: 0, totalEligible: 0})
            )
        );

        // verify that the distribution amounts storage was properly updated
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint40 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }

        // ------------------ 2nd call ------------------
        // prepare the start epoch
        startEpoch = 0;

        // prepare the amounts
        seed = abi.encode(keccak256(seed));
        amounts = new uint128[](amountsLength1);
        totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        uint256 preBalance = MockERC20(reward).balanceOf(address(distributor));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, distributor.currentEpoch() + 1, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), preBalance + totalAmount);

        // verify that the totals storage was properly updated (no time elapsed)
        assertEq(
            abi.encode(distributor.getDistribution(rewarded, reward)),
            abi.encode(BaseRewardStreams.DistributionStorage({lastUpdated: uint40(block.timestamp), accumulator: 0}))
        );
        assertEq(
            abi.encode(distributor.getTotals(rewarded, reward)),
            abi.encode(
                BaseRewardStreams.TotalsStorage({
                    totalRegistered: uint128(preBalance) + totalAmount,
                    totalClaimed: 0,
                    totalEligible: 0
                })
            )
        );

        // verify that the distribution amounts storage was properly updated
        startEpoch = distributor.currentEpoch() + 1;
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint40 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }

        // ------------------ 3rd call ------------------
        // elapse some random amount of time
        vm.warp(blockTimestamp + epochDuration * amountsLength0 + amountsLength1 + amountsLength2);

        // prepare the start epoch
        startEpoch = uint40(
            bound(
                startEpoch, distributor.currentEpoch() + 1, distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD()
            )
        );

        // prepare the amounts
        seed = abi.encode(keccak256(seed));
        amounts = new uint128[](amountsLength2);
        totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        preBalance = MockERC20(reward).balanceOf(address(distributor));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, startEpoch, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), preBalance + totalAmount);

        // verify that the totals storage was properly updated (considering that some has time elapsed)
        {
            BaseRewardStreams.DistributionStorage memory distribution = distributor.getDistribution(rewarded, reward);
            BaseRewardStreams.TotalsStorage memory totals = distributor.getTotals(rewarded, reward);
            assertEq(distribution.lastUpdated, uint40(block.timestamp));
            assertGt(distribution.accumulator, 0);
            assertEq(totals.totalRegistered, uint128(preBalance) + totalAmount);
            assertEq(totals.totalClaimed, 0);
            assertEq(totals.totalEligible, 0);
        }

        // verify that the seeder earned storage was properly updated too
        assertGt(distributor.getEarned(seeder, rewarded, reward).accumulator, 0);

        // verify that the distribution amounts storage was properly updated
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint40 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }
    }

    function test_RevertIfInvalidEpoch_RegisterReward(uint40 blockTimestamp) external {
        vm.assume(
            blockTimestamp > distributor.EPOCH_DURATION()
                && blockTimestamp < type(uint40).max - distributor.EPOCH_DURATION()
        );
        vm.warp(blockTimestamp);

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1;

        vm.startPrank(seeder);
        uint40 startEpoch = distributor.currentEpoch();
        vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = uint40(distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD() + 1);
        vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        // succeeds if the epoch is valid
        vm.startPrank(seeder);
        startEpoch = 0;
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = distributor.currentEpoch() + 1;
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = uint40(distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD());
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();
    }

    function test_RevertIfInvalidAmounts_RegisterReward(uint8 numberOfEpochs) external {
        uint128[] memory amounts = new uint128[](numberOfEpochs);

        // make total amount greater than zero
        if (amounts.length > 0) {
            amounts[0] = 1;
        }

        vm.startPrank(seeder);
        if (amounts.length == 0 || amounts.length > distributor.MAX_DISTRIBUTION_LENGTH()) {
            vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        }
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();

        // total amount is zero which is also invalid
        if (amounts.length > 0) {
            amounts[0] = 0;
        }

        vm.startPrank(seeder);
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();
    }

    function test_RevertIfAccumulatorOverflows_RegisterReward() external {
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1;

        // initialize the distribution data and set the total registered amount to the max value
        BaseRewardStreams.DistributionStorage memory distribution =
            BaseRewardStreams.DistributionStorage({lastUpdated: uint40(1), accumulator: 0});
        BaseRewardStreams.TotalsStorage memory totals = BaseRewardStreams.TotalsStorage({
            totalRegistered: uint128(type(uint160).max / 1e18),
            totalClaimed: 0,
            totalEligible: 0
        });

        distributor.setDistribution(rewarded, reward, distribution);
        distributor.setTotals(rewarded, reward, totals);

        vm.startPrank(seeder);
        vm.expectRevert(BaseRewardStreams.AccumulatorOverflow.selector);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();

        // accumulator doesn't overflow if the total registered amount is less than the max value
        totals.totalRegistered -= 1;
        distributor.setTotals(rewarded, reward, totals);

        vm.startPrank(seeder);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();
    }

    function test_RevertIfMaliciousToken_RegisterReward(uint16[] calldata _amounts) external {
        vm.assume(_amounts.length > 0 && _amounts.length <= distributor.MAX_DISTRIBUTION_LENGTH() && _amounts[0] > 0);

        uint128[] memory amounts = new uint128[](_amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(_amounts[i]);
        }

        address malicious = address(new MockERC20Malicious("Malicious", "MAL"));
        MockERC20(malicious).mint(seeder, type(uint256).max);

        vm.prank(seeder);
        MockERC20(malicious).approve(address(distributor), type(uint256).max);

        vm.startPrank(seeder);
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.registerReward(rewarded, malicious, 0, amounts);
        vm.stopPrank();

        // succeeds if the token is not malicious
        vm.startPrank(seeder);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();
    }
}
