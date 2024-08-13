pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";


contract ERC20Caller {

    function externalTransfer(IERC20 token, address to, uint256 amount) public {
        token.transferFrom(msg.sender,to,amount);
    }
} 