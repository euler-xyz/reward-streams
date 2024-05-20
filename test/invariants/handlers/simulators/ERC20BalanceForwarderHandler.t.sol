// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Contracts
import {BaseHandler} from "../../base/BaseHandler.t.sol";

// Interfaces
import {ERC20, IBalanceForwarder} from "test/utils/MockERC20.sol";

/// @title ERC20BalanceForwarderHandler
/// @notice Handler test contract for the  IRM actions
contract ERC20BalanceForwarderHandler is BaseHandler {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function enableBalanceForwarding() external setup {
        bool success;
        bytes memory returnData;

        (success, returnData) = actor.proxy(
            address(trackingDistributor), abi.encodeWithSelector(IBalanceForwarder.enableBalanceForwarding.selector)
        );

        if (success) {
            assert(true);
        }
    }

    function disableBalanceForwarding() external setup {
        bool success;
        bytes memory returnData;

        (success, returnData) = actor.proxy(
            address(trackingDistributor), abi.encodeWithSelector(IBalanceForwarder.disableBalanceForwarding.selector)
        );

        if (success) {
            assert(true);
        }
    }

    function transfer(uint256 i, uint256 amount) external setup {
        bool success;
        bytes memory returnData;

        address account = _getRandomActor(i);

        (success, returnData) =
            actor.proxy(address(trackingDistributor), abi.encodeWithSelector(ERC20.transfer.selector, account, amount));

        if (success) {
            assert(true);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
