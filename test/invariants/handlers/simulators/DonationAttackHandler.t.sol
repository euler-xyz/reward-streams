// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {MockERC20} from "test/utils/MockERC20.sol";

// Contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler} from "../../base/BaseHandler.t.sol";

/// @title DonationAttackHandler
/// @notice Handler test contract for the  DonationAttack actions
contract DonationAttackHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice This function transfers any amount of assets to a contract in the system
    /// @dev Flashloan simulator
    function donate(uint8 i, uint8 j, uint256 amount) external {
        // Get one of the tsystem assets randomly
        MockERC20 _token = MockERC20(_getRandomAsset(i));

        // Get one of the two setups randomly
        (, address _target) = _getRandomRewards(j);

        _token.mint(address(this), amount);

        _token.transfer(_target, amount);

        _resetTarget();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
