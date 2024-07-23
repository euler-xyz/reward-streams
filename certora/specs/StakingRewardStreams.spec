//// @title Verification of StakingRewardStream 
/* 
 to run:
   certoraRun certora/conf/StakingRewardStream.conf
 see:
    docs.certora.com on CVL and Certora Prover 
 
*/   

import "./ERC20/erc20.spec";

methods {
    // Main contract
    function balanceOf(address, address) external returns (uint256) envfree;
    function rewardAmount(address, address, uint48) external returns (uint256) envfree;
    function totalRewardClaimed(address, address) external returns (uint256) envfree;
    function totalRewardRegistered(address, address) external returns (uint256) envfree;
    function getEpoch(uint48) external returns (uint48) envfree;
    
    // In order to assume msgSender is not EVC and not the current contract, we summarize msgSedner function to return the current msg.sender 
    function EVCUtil._msgSender() internal returns (address) with (env e) => assumeNotEVC(e.msg.sender);

}


/*******  CVL Functions and Definitions  *******/
function assumeNotEVC(address msgSender) returns address {
    require msgSender != currentContract.evc;
    require msgSender != currentContract;
    return msgSender;
} 

definition getEpochCVL(uint256 storageIndex, uint256 slot) returns mathint = storageIndex*2+slot;

/// @title The `SCALER` - since we cannot use constants in quantifiers
definition SCALER() returns uint256 = 2* 10^19;

/// @title The `MAX_EPOCH_DURATION` (70 days) - since we cannot use constants
definition MAX_EPOCH_DURATION() returns uint256 = 10 * 7 * 24 * 60 * 60;

/*******  Ghost and Hooks *******/


/// @notice `sumBalancesPerRewarded[rewarded]` represents the sum of `accounts[account][rewarded].balance` for all account 
ghost mapping(address => mathint) sumBalancesPerRewarded {
    init_state axiom forall address t. sumBalancesPerRewarded[t]==0;
}


/// @notice Hook onto `AccountStorage` to update `sumBalancesPerRewarded`
hook Sstore accounts[KEY address account][KEY address rewarded].balance uint256 value (uint256 oldValue)
{
    sumBalancesPerRewarded[rewarded] = sumBalancesPerRewarded[rewarded] + value - oldValue;
}

/** @notice sumOfNotDistributed[reward] represents the sum of reward token not distributed yet. It is computed as the sum of`totalRegistered` minus the `totalClaimed` 
*/
ghost mapping(address => mathint) sumOfNotDistributed {
    init_state axiom forall address t. sumOfNotDistributed[t]==0;
}


/// @notice Hook onto `DistributionStorage.totalRegistered` to update `sumOfNotDistributed` 
hook Sstore distributions[KEY address rewarded][KEY address reward].totalRegistered uint128 value (uint128 oldValue)
{
    sumOfNotDistributed[reward] = sumOfNotDistributed[reward] + value - oldValue;
}

/// @notice Hook onto `DistributionStorage.totalClaimed` to update `sumOfNotDistributed` 
hook Sstore distributions[KEY address rewarded][KEY address reward].totalClaimed uint128 value (uint128 oldValue)
{
    sumOfNotDistributed[reward] = sumOfNotDistributed[reward] - value + oldValue;
}


/** @notice Partial sum of amounts to distribute per start epoch up to end epoch.
  sumOfAmountPerEpochStartToEpochEnd[rewarded][reward][start-epoch][end-epoch] represents the  of total distribution amount of reward for rewarded between start-epoch to end-epoch (including both start and end epochs)
*/

ghost mapping(address => mapping(address => mapping(mathint => mapping(mathint => mathint)))) sumOfAmountPerEpochStartToEpochEnd {
    init_state axiom    forall address rewarded. 
                        forall address reward.
                        forall mathint start.
                        forall mathint end.
                        sumOfAmountPerEpochStartToEpochEnd[rewarded][reward][start][end] == 0;
}
/** @notice Hook onto `DistributionStorage.amounts` to update `sumOfAmountPerEpochStartToEpochEnd` . A single update to some epoch i updates all 
sumOfAmountPerEpochStartToEpochEnd[j][k] in which j <= i <= k
*/
hook Sstore distributions[KEY address _rewarded][KEY address _reward].amounts[KEY uint256 storageIndex][INDEX uint256 slot] uint128 value (uint128 oldValue) {
     havoc sumOfAmountPerEpochStartToEpochEnd assuming
            forall address rewarded. 
            forall address reward.
            forall mathint start.
            forall mathint end.
                sumOfAmountPerEpochStartToEpochEnd@new[rewarded][reward][start][end] ==
                sumOfAmountPerEpochStartToEpochEnd@old[rewarded][reward][start][end] +
                (
                    // if it is the update rewarded, reward and the epoch is in between the start and the end, update the ghost 
                (rewarded == _rewarded && reward == _reward && start >= getEpochCVL(storageIndex, slot) && end <= getEpochCVL(storageIndex, slot)) ?
                 (value - oldValue) : 0 
                );

}

/*******  Valid State  *******/



/// @title `EPOCH_DURATION` is not larger than `MAX_EPOCH_DURATION`
invariant EpochDurationSizeLimit()
    currentContract.EPOCH_DURATION <= MAX_EPOCH_DURATION();


/// @title Each sumOfAmountPerEpochStartToEpochEnd is less than the corresponding totalRegistered 
invariant epochSumsLETotalRegistered() 
    forall address rewarded. 
    forall address reward.
    forall mathint start.
    forall mathint end.
    sumOfAmountPerEpochStartToEpochEnd[rewarded][reward][start][end] <= to_mathint(currentContract.distributions[rewarded][reward].totalRegistered);


/// @title `totalRewardRegistered` is limited 
/// totalRewardRegistered(rewarded, reward) * SCALER() <= max_uint160;
invariant totalRegisteredMaxValue()
    (
        forall address rewarded. forall address reward.
        to_mathint(currentContract.distributions[rewarded][reward].totalRegistered) * SCALER() <= max_uint160
    ) {
        preserved {
            requireInvariant epochSumsLETotalRegistered();
        }
    }


/// @title Reward amount per epoch is not greater than total registered reward
invariant rewardAmountLessThanTotal(address rewarded, address reward, uint48 epoch)
    rewardAmount(rewarded, reward, epoch) <= totalRewardRegistered(rewarded, reward);



/*******  High Level Properties  *******/


/** @title Invariant: reward token solvency.
The expected balance of rewarded and reward token:
reward.balanceOf(this) === forall rewarded : sum of (totalRegistered - totalClaimed ) 
rewarded.balanceOf(this) === sum forall account balanceOf(account,rewarded);

The same token can be both a reward and rewarded. 
*/

invariant solvency(address token) 
    to_mathint(externalBalanceOf(token, currentContract)) >=  sumBalancesPerRewarded[token] + sumOfNotDistributed[token]

    {
        preserved ERC20Caller.externalTransfer(address erc20, address to, uint256 amount) with (env e) {
            //assume ( better to prove this) that current contract does not have a dynamic call 
            require e.msg.sender != currentContract;
        }
    }
    


/*******  Staking Properties  *******/

/// @title Staking increases staked balance by given amount
rule stakeIntegrity(address rewarded, uint256 amount) {
    env e;
    require e.msg.sender != currentContract.evc;
    uint256 preBalance = balanceOf(e.msg.sender, rewarded);

    stake(e, rewarded, amount);

    uint256 postBalance = balanceOf(e.msg.sender, rewarded);

    assert (
        amount != max_uint256 => to_mathint(postBalance) == preBalance + amount,
        "Staking increases staked balance by given amount"
    );
}


/*******  Rewards Properties  *******/
/// @title An example showing rewards can be given
rule canBeRewarded(address rewarded, address reward, address recipient, bool forfeitRecentReward) {
    uint256 preBalance = externalBalanceOf(rewarded, recipient);

    env e;
    claimReward(e, rewarded, reward, recipient, forfeitRecentReward);

    uint256 postBalance = externalBalanceOf(rewarded, recipient);
    satisfy postBalance > preBalance;
}


/// @title Those that stake more should earn more rewards
rule stakeMoreEarnMore(
    address staker1,
    address staker2,
    address rewarded,
    address reward,
    bool forfeitRecentReward
) {
    env e1;
    env e2;
    

    uint256 earned1 = earnedReward(e1, staker1, rewarded, reward, forfeitRecentReward);
    uint256 earned2 = earnedReward(e2, staker1, rewarded, reward, forfeitRecentReward);

    require e2.block.timestamp > e1.block.timestamp;
    uint256 earned1Late = earnedReward(e1, staker1, rewarded, reward, forfeitRecentReward);
    uint256 earned2Late = earnedReward(e2, staker1, rewarded, reward, forfeitRecentReward);

    mathint diff1 = earned1Late - earned1;
    mathint diff2 = earned2Late - earned2;

    assert (
        balanceOf(staker1, rewarded) > balanceOf(staker2, rewarded) => diff1 >= diff2,
        "stake more earn more"
    );

    satisfy (
        balanceOf(staker1, rewarded) > balanceOf(staker2, rewarded) => diff1 > diff2
    );
}


/// @title Staking and immediately unstaking should not yield profit
rule stakeUnStakeNoBonus(uint256 amount, address token, address staker, bool forfeitRecentReward) {

    require amount < max_uint256;
    uint256 preBalance = externalBalanceOf(token, staker);

    env e;
    require e.msg.sender == staker;
    stake(e, token, amount);
    unstake(e, token, amount, staker, forfeitRecentReward);

    uint256 postBalance = externalBalanceOf(token, staker);
    assert (
        postBalance <= preBalance,
        "staking and immediately un-staking should give no reward"
    );
}



// ---- Claimed and total reward -----------------------------------------------

/// @title Total claimed is non-decreasing
rule totalClaimedIsNonDecreasing(method f, address rewarded, address reward) {
    uint256 preClaimed = totalRewardClaimed(rewarded, reward);

    env e;
    calldataarg args;
    f(e, args);

    uint256 postClaimed = totalRewardClaimed(rewarded, reward);
    assert (postClaimed >= preClaimed, "total claimed is non-decreasing");
}


/// @title Staked balance is reduced only by calling `unstake`
rule stakedReduceProperty(method f, address account, address rewarded) {
    uint256 preBalance = balanceOf(account, rewarded);

    env e;
    calldataarg args;
    f(e, args);

    uint256 postBalance = balanceOf(account, rewarded);
    assert (
        postBalance < preBalance =>
        f.selector == sig:unstake(address, uint256, address, bool).selector,
        "staked reduced only by unstake"
    );
}

    

