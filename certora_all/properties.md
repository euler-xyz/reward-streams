
## uint-test:
* Integrity of f
* stake(r, x); stake(r, y) === stake(r, x+ y)  
            comparing only internal balance -  easy
            compare also balances external - harder
            all storage 
* unstake(r, x, to, b); unstake(r, y, to, b) === unstake(r, x+ y, to, b)
* earnedReward(...) ==  change to balance due to claimReward(...); 
* earnedReward(...) <= totalRewardRegistered(...)


## valid-state: 
  * for each (reard, rewarded) totalRegistered >= totalClaimed
  * totalRegistered sum of amounts 

## state change:
* disableReward() => no change to enable return
f();


(rewarded, reward) : not-registered, registered, registered and active, registered and not active 

per user (rewarded, reward) : enable - per user, disable - per user, not-claimable, earned ,

epoch: not-yet, active, over

## variable change:
* accumulator is update together lasttimestamp 

## risk-assessment:
* double claim 

token.balanceOf(this) >= ...


user.accumulated == 0 => f() ; earnedReward() == 0 even if time elapses 
## high level:
==========

token.balanceOf(this) decrease =>
 balanceOf(e.msg.sender, token) decrease  ||
 earnedReward(e.msg.sender || 0 , X , token, b) should decrease 


// no free lunch:

if no time elapes total assets of user should not change:
token.balanceOf(user) + balanceOf(user, token) + earnedReward(user, all token, token)

/* reward token */
reward.balanceOf(this) == forall rewarded : sum of (totalRegistered - totalClaimed ) 
rewarded.balanceOf(this) == sum balanceOf(account,rewarded);

========== community review =========
https://github.com/0xgreywolf/euler-vault-cantina-fv/tree/competition-official

https://prover.certora.com/output/541734/71448b9ab45d4917a768c4a6b1ddb085/?anonymousKey=97ed825f33895e86082418bc7cc900718bca528a 
0xGreyWolf earned 95$ 

alexzoid 
https://github.com/alexzoid-eth/euler-vault-cantina-fv/tree/master/certora/specs

https://prover.certora.com/output/52567/e045e959a0554172878936bb6a12953d/?anonymousKey=5796c3ed8001f3f4a3dac91d14252521910383dc


found almost all 