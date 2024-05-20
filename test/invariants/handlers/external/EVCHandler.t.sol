// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {EthereumVaultConnector} from "evc/EthereumVaultConnector.sol";

// Testing contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler, EnumerableSet} from "../../base/BaseHandler.t.sol";

/// @title EVCHandler
/// @notice Handler test contract for the EVC actions
contract EVCHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
    function setAccountOperator(uint8 i, uint8 j, bool authorised) external setup {
        bool success;
        bytes memory returnData;

        address account = _getRandomActor(i);

        address operator = _getRandomActor(j);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.setAccountOperator.selector, account, operator, authorised)
        );

        if (success) {
            assert(true);
        }
    }

    // COLLATERAL

    function enableCollateral(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.enableCollateral.selector, account, trackingRewarded)
        );

        if (success) {
            assert(true);
        }
    }

    function disableCollateral(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.disableCollateral.selector, account, trackingRewarded)
        );

        if (success) {
            assert(true);
        }
    }

    // CONTROLLER

    function enableController(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.enableController.selector, account, address(controller))
        );

        if (success) {
            assert(true);
        }
    }

    function disableControllerEVC(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address[] memory controllers = evc.getControllers(account);

        (success, returnData) = actor.proxy(
            address(evc), abi.encodeWithSelector(EthereumVaultConnector.disableController.selector, account)
        );

        address[] memory controllersAfter = evc.getControllers(account);
        if (controllers.length == 0) {
            assertTrue(success);
            assertTrue(controllersAfter.length == 0);
        } else {
            assertEq(controllers.length, controllersAfter.length);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
