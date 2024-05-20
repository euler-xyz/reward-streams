// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {Vm} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

// Utils
import {Actor} from "../utils/Actor.sol";
import {PropertiesConstants} from "../utils/PropertiesConstants.sol";
import {StdAsserts} from "../utils/StdAsserts.sol";

// Base
import {BaseStorage, BaseRewardStreamsHarness} from "./BaseStorage.t.sol";

// Interfaces
import {IRewardStreams} from "src/interfaces/IRewardStreams.sol";

/// @notice Base contract for all test contracts extends BaseStorage
/// @dev Provides setup modifier and cheat code setup
/// @dev inherits Storage, Testing constants assertions and utils needed for testing
abstract contract BaseTest is BaseStorage, PropertiesConstants, StdAsserts, StdUtils {
    bool public IS_TEST = true;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   ACTOR PROXY MECHANISM                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Actor proxy mechanism
    modifier setup() virtual {
        actor = actors[msg.sender];
        _;
        actor = Actor(payable(address(0)));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     CHEAT CODE SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev Cheat code address, 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D.
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    Vm internal constant vm = Vm(VM_ADDRESS);

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          HELPERS                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _getZeroAddressRewards(
        address _rewarded,
        address _reward,
        address _target
    ) internal view returns (uint256) {
        BaseRewardStreamsHarness.EarnStorage memory earnStorage =
            BaseRewardStreamsHarness(_target).getAccountEarnedData(address(0), _rewarded, _reward);
        return earnStorage.claimable;
    }

    function _getDistributionAccumulator(
        address _rewarded,
        address _reward,
        address _target
    ) internal view returns (uint256) {
        return BaseRewardStreamsHarness(_target).getUpdatedAccumulator(_rewarded, _reward);
    }

    /// @notice Helper function that returns either the staking or tracking reward setup and sets the target
    function _getRandomRewards(uint256 _i) internal returns (address rewarded, address distributor) {
        if (_i % 2 == 0) {
            rewarded = stakingRewarded;
            distributor = address(stakingDistributor);
        } else {
            rewarded = trackingRewarded;
            distributor = address(trackingDistributor);
        }
        _setTarget(distributor);
    }

    function _distributionActive(address rewarded, address _rewards, address _target) internal view returns (bool) {
        (uint48 lastUpdated,,,,) = BaseRewardStreamsHarness(_target).getDistributionData(rewarded, _rewards);
        return lastUpdated > 0;
    }

    function _enabledRewards(address account, address rewarded, address _target) internal view returns (bool) {
        address[] memory enabledRewards = IRewardStreams(_target).enabledRewards(account, rewarded);
        return enabledRewards.length > 0;
    }

    function _getSetupData(uint256 _i) internal view returns (address, address) {
        Setup memory _setup = distributionSetups[_i];
        return (_setup.rewarded, _setup.distributor);
    }

    function _getRandomAsset(uint256 _i) internal view returns (address) {
        uint256 _assetIndex = _i % assetAddresses.length;
        return assetAddresses[_assetIndex];
    }

    function _getRandomActor(uint256 _i) internal view returns (address) {
        uint256 _actorIndex = _i % NUMBER_OF_ACTORS;
        return actorAddresses[_actorIndex];
    }

    function _makeAddr(string memory name) internal pure returns (address addr) {
        uint256 privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = vm.addr(privateKey);
    }

    function _setTarget(address _target) internal {
        target = BaseRewardStreamsHarness(_target);
    }

    function _resetTarget() internal {
        target = BaseRewardStreamsHarness(address(0));
    }
}
