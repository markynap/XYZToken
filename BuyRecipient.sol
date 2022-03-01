//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";

contract FeeReceiver is Ownable {

    IERC20 public token;

    string public Type;

    /**
        Type As In BuyReceiver, SellReceiver, TransferReceiver - for tracking
     */
    constructor(string memory _Type){
        Type = _Type;
    }


    function trigger() external {




    }

    function pairToken(address _token) external onlyOwner {
        require(address(token) == address(0) && _token != address(0), 'Already Paired');
        token = IERC20(_token);
    }

}