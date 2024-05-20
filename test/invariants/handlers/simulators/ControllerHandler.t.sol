// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Mock Contracts
import {MockController} from "test/utils/MockController.sol";

/// @title ControllerHandler
/// @notice Handler test contract for the  IRM actions
contract ControllerHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function liquidateCollateralShares(uint8 i, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address liquidated = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(controller),
            abi.encodeWithSelector(
                MockController.liquidateCollateralShares.selector,
                trackingRewarded,
                liquidated,
                trackingRewarded,
                amount
            )
        );

        if (success) {
            assert(true);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
